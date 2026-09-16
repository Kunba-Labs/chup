import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';

test('development relay enforces authentication and rejects malformed input locally', async (t) => {
 const appToken = 'test-only-token-'.repeat(4);
 const child = spawn(process.execPath,[new URL('../server.mjs',import.meta.url).pathname],{env:{...process.env,OPENAI_API_KEY:'test-only-not-a-provider-key',CHUP_TOKEN:appToken,PORT:'0'},stdio:['ignore','pipe','pipe']});
 t.after(()=>child.kill('SIGTERM'));
 const port = await new Promise((resolve,reject)=>{
  let text=''; const timeout=setTimeout(()=>reject(new Error('Test relay startup timed out')),5000);
  child.stdout.on('data',data=>{text+=data;const match=text.match(/127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timeout);resolve(Number(match[1]));}});
  child.on('error',reject);child.on('exit',code=>{if(code)reject(new Error('Test relay exited before listening'));});
 });
 const url = `http://127.0.0.1:${port}`;
 assert.equal((await fetch(url+'/missing',{method:'POST',body:'{}'})).status,401);
 const headers={Authorization:`Bearer ${appToken}`,'Content-Type':'application/json'};
 assert.equal((await fetch(url+'/missing',{method:'POST',headers,body:'{}'})).status,404);
 assert.equal((await fetch(url+'/ask',{method:'POST',headers,body:'not json'})).status,400);
 assert.equal((await fetch(url+'/transcribe',{method:'POST',headers,body:'{}'})).status,400);
 // No valid provider request is made in this test.
});
