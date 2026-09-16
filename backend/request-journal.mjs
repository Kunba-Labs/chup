import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {mkdirSync,readFileSync,writeFileSync,renameSync,openSync,closeSync,fsyncSync,existsSync,readdirSync} from 'node:fs';
import path from 'node:path';
import {AsyncLocalStorage} from 'node:async_hooks';
export class RequestJournal {
  constructor(directory, namespace='default') {
    this.root=path.resolve(directory); mkdirSync(this.root,{recursive:true,mode:0o700});
    const keyFile=path.join(this.root,'journal.key');
    if(!existsSync(keyFile)&&readdirSync(this.root).some(name=>/^[a-f0-9]{64}$/.test(name)))throw new Error('Request-journal key is missing. Restore the original key; encrypted jobs were preserved.');
    if(!existsSync(keyFile)){
      const fd=openSync(keyFile,'wx',0o600);
      try {writeFileSync(fd,randomBytes(32));fsyncSync(fd);}finally{closeSync(fd);}
      const directory=openSync(this.root,'r');try{fsyncSync(directory);}finally{closeSync(directory);}
    }
    this.key=readFileSync(keyFile); if(this.key.length!==32)throw new Error('Invalid request-journal key.');
    this.directory=path.join(this.root,createHash('sha256').update(namespace).digest('hex'));mkdirSync(this.directory,{recursive:true,mode:0o700});
    this.context=new AsyncLocalStorage();this.inflight=new Map();
  }
  file(id) { return path.join(this.directory,createHash('sha256').update(id).digest('hex')+'.sealed'); }
  read(id) {
    if(!existsSync(this.file(id)))return null;
    return this.decode(readFileSync(this.file(id)));
  }
  decode(raw) {
    const dec=createDecipheriv('aes-256-gcm',this.key,raw.subarray(0,12));dec.setAuthTag(raw.subarray(12,28));
    return JSON.parse(Buffer.concat([dec.update(raw.subarray(28)),dec.final()]).toString());
  }
  write(value) {
    if(value.status!=='forgotten'&&this.read(value.id)?.status==='forgotten')throw new Error('This request was deleted.');
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',this.key,iv),data=Buffer.concat([cipher.update(JSON.stringify(value)),cipher.final()]);
    const file=this.file(value.id),temp=file+'.'+randomBytes(8).toString('hex');
    const fd=openSync(temp,'wx',0o600);try{writeFileSync(fd,Buffer.concat([iv,cipher.getAuthTag(),data]));fsyncSync(fd);}finally{closeSync(fd);}
    renameSync(temp,file);const dir=openSync(this.directory,'r');try{fsyncSync(dir);}finally{closeSync(dir);}
  }
  forget(ids) {
    if(!Array.isArray(ids)||ids.length>10000||ids.some(id=>typeof id!=='string'||!/^[a-zA-Z0-9_/-]{1,180}$/.test(id)))throw new Error('Invalid deletion scope.');
    for(const id of ids){const old=this.read(id);this.write({id,fingerprint:old?.fingerprint??'',created:Date.now(),status:'forgotten',steps:[]});}
  }
  expire(days=30) {
    if(!Number.isFinite(days)||days<1)throw new Error('Journal retention must be at least one day.');
    for(const file of readdirSync(this.directory)){
      if(!file.endsWith('.sealed'))continue;
      const job=this.decode(readFileSync(path.join(this.directory,file)));
      if(job.status!=='forgotten'&&Date.now()-job.created>days*86400000&&!this.inflight.has(job.id))this.forget([job.id]);
    }
  }
  async run(id,fingerprint,work) {
    if(!/^[a-zA-Z0-9_/-]{1,180}$/.test(id))throw new Error('Invalid durable request ID.');
    const existing=this.read(id);if(existing&&existing.fingerprint!==fingerprint)throw new Error('Request ID collision.');
    if(this.inflight.has(id))return this.inflight.get(id);
    if(existing?.status==='forgotten'){const error=new Error('This request was deleted. Start a new addressed request if needed.');error.statusCode=410;throw error;}
    const job=existing??{id,fingerprint,steps:[],created:Date.now(),status:'running'};
    if(job.status==='completed')return job.result;
    const task=this.context.run({job,index:0},async()=>{
      try{const result=await work();job.result=result;job.status='completed';this.write(job);return result;}
      catch(e){e.usage=this.usage();job.status='interrupted';this.write(job);throw e;}
    });this.inflight.set(id,task);
    try{return await task;}finally{this.inflight.delete(id);}
  }
  async step(model,category,work) {
    const current=this.context.getStore();if(!current)return work();
    const index=current.index++,job=current.job,old=job.steps[index];
    if(old?.status==='completed')return old.value;
    if(old?.status==='pending'){const error=new Error('Provider result is unconfirmed. This request will not be charged again automatically. Review usage before starting a new request.');error.statusCode=409;throw error;}
    const step={id:job.id+'/'+index,model,category,status:'pending'};job.steps[index]=step;this.write(job);
    // An exception keeps this step pending: the provider may have accepted the request.
    const value=await work();step.value=value;step.status='completed';this.write(job);return value;
  }
  usage() {
    const current=this.context.getStore();if(!current)return [];
    return current.job.steps.map(s=>{
      const u=s.value?.usage??{};
      return {created:Date.now(),id:s.id,category:s.category,model:s.model,inputTokens:u.input_tokens??null,cachedTokens:u.input_tokens_details?.cached_tokens??null,outputTokens:u.output_tokens??null,seconds:u.seconds??null,confirmed:s.value?.usage!=null,raw:JSON.stringify(u)};
    });
  }
}
