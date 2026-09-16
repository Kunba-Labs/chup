import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';

test('disconnecting an assistant request aborts provider work', async t=>{
 const token='test-only-app-token-'.repeat(3);
 const child=spawn(process.execPath,['--import',new URL('./fixtures/provider-stub.mjs',import.meta.url).href,new URL('../server.mjs',import.meta.url).pathname],{env:{...process.env,OPENAI_API_KEY:'test-only',CHUP_TOKEN:token,PORT:'0'},stdio:['ignore','pipe','pipe','ipc']});
 t.after(()=>child.kill('SIGTERM'));
 const waitMessage=expected=>new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error('Missing '+expected)),5000);
  const handler=message=>{if(message===expected){clearTimeout(timeout);child.off('message',handler);resolve();}};
  child.on('message',handler);
 });
 const port=await new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error('Server did not start')),5000);
  child.stdout.on('data',data=>{const match=data.toString().match(/127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});
 });
 const started=waitMessage('provider-started');const aborted=waitMessage('provider-aborted');
 const controller=new AbortController();
 const request=fetch(`http://127.0.0.1:${port}/ask`,{method:'POST',signal:controller.signal,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({question:'What was decided?',segments:[],note:'',history:[]})});
 await started;controller.abort();await assert.rejects(request);await aborted;
});
