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
test('semantic rejection drops a claim even when its quotation exists, keeping the rest',async()=>{
  const two={items:[summary.items[0],{...summary.items[0],id:'kept'}]};
  const engine=createIntelligence(async(name)=>name==='evidence_check'?{verdicts:[{id:'fact',supported:false},{id:'kept',supported:true}]}:two);
  assert.deepEqual((await engine.summarize([segment])).items.map(i=>i.id),['kept']);
});
test('enhanced notes keep user lines verbatim, drop reworded or unsupported AI lines',async()=>{
  const note='# Launch\n  pricing??\nSam owns rollout\nSam owns rollout';
  const engine=createIntelligence(async(name)=>name==='evidence_check'
    ?{verdicts:[{id:'a1',supported:true},{id:'a2',supported:false}]}
    :{blocks:[
      {id:'h',kind:'user',text:'# Launch',sources:[]},
      {id:'u',kind:'user',text:'Pricing questions',sources:[]},
      {id:'x',kind:'heading',text:'Migration completed by Sam',sources:[]},
      {id:'bad',kind:'ai',text:'Fabricated.',sources:[{segmentID:'other',quote:'nope'}]},
      {id:'a1',kind:'ai',text:'No Friday launch was agreed.',sources:[{segmentID:segment.id,quote:segment.text}]},
      {id:'a2',kind:'ai',text:'Launch is Friday.',sources:[{segmentID:segment.id,quote:segment.text}]},
    ]});
  const {blocks}=await engine.enhance({segments:[segment],note,template:'general'});
  assert.deepEqual(blocks.map(b=>[b.kind,b.text]),[
    ['user','# Launch'],['ai','No Friday launch was agreed.'],
    ['heading','From your notes'],['user','  pricing??'],['user','Sam owns rollout'],['user','Sam owns rollout'],
  ]);
  await assert.rejects(engine.enhance({segments:[segment],note,template:'nope'}),/Unknown notes template/);
  const reordered=createIntelligence(async(name)=>name==='evidence_check'?{verdicts:[]}:{blocks:[
    {id:'b',kind:'user',text:'second',sources:[]},{id:'a',kind:'user',text:'first',sources:[]}]});
  assert.deepEqual((await reordered.enhance({segments:[segment],note:'first\nsecond'})).blocks.map(b=>b.text),['first','second']);
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
