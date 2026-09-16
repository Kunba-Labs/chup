import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createIntelligence, outlineEvidence} from '../intelligence.mjs';
const segment = {id:'meeting:s1',meetingID:'meeting',text:'We did not agree to ship Friday.',start:2,end:4,provisional:false};
const summary = {items:[{id:'fact',text:'No Friday launch was agreed.',sources:[{segmentID:segment.id,quote:segment.text}]}]};

test('live outline uses independent evidence copies; final transcript remains provisional',()=>{
  const live={...segment,provisional:true};
  assert.equal(outlineEvidence([live])[0].provisional,false);
  assert.equal(live.provisional,true);
  assert.throws(()=>outlineEvidence([{...live,start:-1}]));
});
test('semantic rejection prevents saving a claim even when its quotation exists',async()=>{
  const engine=createIntelligence(async(name)=>name==='evidence_check'?{supported:false}:summary);
  await assert.rejects(engine.summarize([segment]),/unsupported generated claim/);
});
test('retrieval keeps original ordering and contradictory evidence, rejects foreign source IDs',async()=>{
  const segments=Array.from({length:4},(_,i)=>({...segment,id:'s'+i,text:(i%2?'Do not launch. ':'Launch. ')+ 'x'.repeat(30000)}));
  const seen=[];
  const engine=createIntelligence(async(name,schema,instructions,input)=>{
    seen.push(input.segments);
    return {ids:input.segments.map(s=>s.id).reverse()};
  });
  assert.deepEqual(await engine.retrieve('Launch?',segments),segments);
  assert.equal(seen.length,4);
  const bad=createIntelligence(async()=>({ids:['another-meeting:s1']}));
  await assert.rejects(bad.retrieve('Launch?',segments),/foreign source/);
});
test('HTTP outline route is wired and authenticated; empty evidence invokes no provider',async(t)=>{
  const token='fixture-token-no-secret-32-characters';
  const child=spawn(process.execPath,['server.mjs'],{
    cwd:new URL('..',import.meta.url),
    env:{...process.env,PORT:'0',CHUP_TOKEN:token,OPENAI_API_KEY:'fixture-never-used'},
    stdio:['ignore','pipe','pipe']
  });
  t.after(()=>child.kill());
  const port=await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Backend fixture failed to start')),5000);
    child.on('exit',code=>{clearTimeout(timer);reject(new Error('Backend exited '+code));});
    child.stdout.on('data',chunk=>{
      const match=chunk.toString().match(/127\.0\.0\.1:(\d+)/);
      if(match){clearTimeout(timer);resolve(match[1]);}
    });
  });
  const url=`http://127.0.0.1:${port}/outline`;
  assert.equal((await fetch(url,{method:'POST',body:'[]'})).status,401);
  const response=await fetch(url,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:'[]'});
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{items:[],_chup:{usage:[]}});
});
