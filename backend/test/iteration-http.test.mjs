import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';

test('HTTP adapter forwards diarization references and rejects unfaithful cleanup', async t => {
  const token = 'test-only-app-token-'.repeat(3);
  const child = spawn(process.execPath,['--import',new URL('./fixtures/iteration-provider.mjs',import.meta.url).href,new URL('../server.mjs',import.meta.url).pathname],{env:{...process.env,OPENAI_API_KEY:'test-only',CHUP_TOKEN:token,PORT:'0'},stdio:['ignore','pipe','pipe']});
  t.after(()=>child.kill('SIGTERM'));
  const port = await new Promise((resolve,reject)=>{
    const timeout = setTimeout(()=>reject(new Error('Server did not start')),5000);
    child.stdout.on('data',data=>{const match=data.toString().match(/127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});
  });
  const request = body => fetch(`http://127.0.0.1:${port}${body.path}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(body.data)});
  const wave=Buffer.alloc(96044);wave.write('RIFF');wave.writeUInt32LE(wave.length-8,4);wave.write('WAVEfmt ',8);wave.writeUInt32LE(16,16);wave.writeUInt16LE(1,20);wave.writeUInt16LE(1,22);wave.writeUInt32LE(24000,24);wave.writeUInt32LE(48000,28);wave.writeUInt16LE(2,32);wave.writeUInt16LE(16,34);wave.write('data',36);wave.writeUInt32LE(wave.length-44,40);
  const diarization = await request({path:'/transcribe',data:{audio:wave.toString('base64'),diarize:true,references:[{name:'voice_a',audio:wave.toString('base64')}]}});
  assert.equal(diarization.status,200);assert.equal((await diarization.json()).segments[0].speaker,'voice_a');
  const cleanup=await request({path:'/dictation',data:{text:'We did not agree on 12 September.',mode:'Light cleanup',selection:'',instruction:'',personalization:[]}});
  assert.notEqual(cleanup.status,200);assert.match((await cleanup.json()).error,/meaning-preservation/);
});
