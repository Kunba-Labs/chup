// Explicit, bounded real-provider smoke test. No personal recordings or app data are read.
import {spawn} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {WebSocket} from 'ws';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.join(root,'.artifacts/provider-qualification.json');
const models=['gpt-live-1','gpt-live-transcribe','gpt-4o-transcribe-diarize','gpt-transcribe',process.env.REASONING_MODEL||'gpt-5.6-luna'];
if(!process.env.OPENAI_API_KEY)throw Error('OPENAI_API_KEY must be set on this trusted host.');
const results={created:new Date().toISOString(),syntheticOnly:true,checks:[]};
async function check(name,work){try{const value=await work();results.checks.push({name,passed:true,...value});console.log('PASS:',name);}catch(e){results.checks.push({name,passed:false,error:String(e.message).slice(0,500)});console.log('FAIL:',name);}}
await check('account-model-access',async()=>{const r=await fetch('https://api.openai.com/v1/models',{headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`},signal:AbortSignal.timeout(20000)});const data=await r.json();if(!r.ok)throw Error('Model lookup status '+r.status);const missing=models.filter(model=>!data.data?.some(item=>item.id===model));if(missing.length)throw Error('Models missing: '+missing.join(', '));return {models};});
if(process.argv.includes('--run')){
 const token=randomBytes(32).toString('hex');
 const journal=path.join(root,'.artifacts/provider-journal-'+randomUUID());
 const child=spawn(process.execPath,[path.join(root,'backend/server.mjs')],{env:{...process.env,CHUP_TOKEN:token,PORT:'0',CHUP_JOURNAL_DIR:journal},stdio:['ignore','pipe','pipe']});
 try{
  const port=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Relay startup timeout')),10000);child.stdout.on('data',chunk=>{const match=chunk.toString().match(/127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});child.once('exit',()=>{clearTimeout(timer);reject(Error('Relay failed to start'));});});
  async function request(route,body,id=randomUUID()){
   const r=await fetch(`http://127.0.0.1:${port}/${route}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Chup-Request-ID':id},body:JSON.stringify(body),signal:AbortSignal.timeout(180000)});
   const value=await r.json();if(!r.ok)throw Error(`Relay ${route} status ${r.status}: ${value.error??'No result'}`);return value;
  }
  for(const language of ['en','nl'])await check('file-transcription-'+language,async()=>{
   const value=await request('transcribe',{audio:readFileSync(path.join(root,'.artifacts/provider-fixtures',language+'.wav')).toString('base64'),diarize:false,languages:[language],keywords:['USB']});
   if(!value.text?.trim())throw Error('Empty transcript');return {text:value.text,usage:value._chup?.usage};
  });
  await check('file-diarization',async()=>{const value=await request('transcribe',{audio:readFileSync(path.join(root,'.artifacts/provider-fixtures/speakers.wav')).toString('base64'),diarize:true,languages:['en','nl']});if(!value.segments?.length||value.segments.some(s=>!Number.isFinite(s.start)||!Number.isFinite(s.end)||s.end<s.start))throw Error('No valid timed segments');return {segments:value.segments,usage:value._chup?.usage};});
  const segments=[{id:'fixture-decision',meetingID:'fixture',start:0,end:5,text:'We decided not to launch on Friday. We need to test three USB microphones.',speakerID:'unknown',track:'microphone',provisional:false}];
  await check('evidence-summary-and-durable-replay',async()=>{const id=randomUUID();const value=await request('summary',segments,id);const replay=await request('summary',segments,id);if(!value.items?.length||JSON.stringify(replay)!==JSON.stringify(value))throw Error('Missing summary or changed cached replay');return {items:value.items,usage:value._chup?.usage};});
  async function socketCheck(live){
   return new Promise((resolve,reject)=>{
    const ws=new WebSocket(`ws://127.0.0.1:${port}/${live?'live':'live-transcribe'}`,{headers:{Authorization:`Bearer ${token}`}});
    const events=[];let completed=false,started=false,usage=null;let interval;
    const timeout=setTimeout(()=>finish(Error('Voice check timed out')),25000);
    function finish(error){if(completed)return;completed=true;clearTimeout(timeout);clearInterval(interval);ws.terminate();error?reject(error):resolve({events,usage});}
    ws.on('error',()=>finish(Error('Voice WebSocket failed')));
    ws.on('close',()=>{if(!completed)finish(Error('Voice closed before required final event'));});
    ws.on('message',raw=>{try{const event=JSON.parse(raw);events.push(event.type);if(event.type==='error')return finish(Error(event.error?.message||'Provider voice error'));
     if(!started&&event.type===(live?'session.started':'session.updated')){
      started=true;
      if(live){ws.send(JSON.stringify({type:'session.input_audio.mute',event_id:randomUUID()}));ws.send(JSON.stringify({type:'session.input_audio.append',audio:Buffer.alloc(2400).toString('base64')}));setTimeout(()=>{if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify({type:'session.close',event_id:randomUUID()}));},750);}
      else {const pcm=readFileSync(path.join(root,'.artifacts/provider-fixtures/en.pcm'));let offset=0;interval=setInterval(()=>{if(ws.readyState!==WebSocket.OPEN)return;if(offset>=pcm.length){clearInterval(interval);ws.send(JSON.stringify({type:'input_audio_buffer.commit'}));return;}ws.send(JSON.stringify({type:'input_audio_buffer.append',audio:pcm.subarray(offset,offset+4800).toString('base64')}));offset+=4800;},100);}
     }
     if(live&&event.type==='session.closed'){usage=event.usage??null;finish();}
     if(!live&&event.type==='conversation.item.input_audio_transcription.completed'){usage=event.usage??null;if(!event.transcript?.trim())finish(Error('Empty live transcript'));else finish();}
    }catch(e){finish(e);}});
   });
  }
  await check('gpt-live-1-start-mute-close',()=>socketCheck(true));
  await check('gpt-live-transcribe-live-audio',()=>socketCheck(false));
 }finally{child.kill('SIGTERM');}
}
mkdirSync(path.dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(results,null,2)+'\n',{mode:0o600});
console.log('Qualification report:',output);if(results.checks.some(x=>!x.passed))process.exitCode=1;
