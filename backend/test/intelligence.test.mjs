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
test('meeting title is one clean line from the summary and rejects empty input',async()=>{
  const engine=createIntelligence(async(name,schema,instructions,input)=>{
    assert.equal(name,'meeting_title'); assert.deepEqual(input.people,['Rizwan']);
    return {title:' "Porting Verna to the new\nstaging setup with Rizwan" '};
  });
  assert.equal((await engine.title({points:['Verna is being ported'],people:['Rizwan']})).title,'Porting Verna to the new staging setup with Rizwan');
  await assert.rejects(engine.title({points:[]}));
});

test('speaker names need a quote containing the name and survive the check',async()=>{
  const segments=[{id:'a',speakerID:'s1',text:'Hoi, ik ben Mo van Align.',start:0,end:2},{id:'b',speakerID:'s2',text:'Astrid, zijn jullie daar nog?',start:2,end:4},{id:'c',speakerID:'s3',text:'Ja, ik ben er.',start:4,end:5}];
  const engine=createIntelligence(async(name,schema,instructions,input)=>{
    if(name==='speaker_names') return {names:[
      {speakerID:'s1',name:'Mo',sources:[{segmentID:'a',quote:'ik ben Mo'}]},
      {speakerID:'s3',name:'Astrid',sources:[{segmentID:'b',quote:'Astrid, zijn jullie daar nog?'},{segmentID:'c',quote:'Ja, ik ben er.'}]},
      {speakerID:'s2',name:'Peter',sources:[{segmentID:'b',quote:'zijn jullie'}]},
      {speakerID:'ghost',name:'Kim',sources:[{segmentID:'a',quote:'Mo'}]},
      {speakerID:'s1',name:'Mohammed',sources:[{segmentID:'a',quote:'invented'}]}]};
    assert.equal(name,'speaker_check');
    assert.deepEqual(input.names.map(n=>n.speakerID),['s1','s3']);
    return {verdicts:[{speakerID:'s1',supported:true},{speakerID:'s3',supported:false}]};
  });
  const result=await engine.speakers({segments});
  assert.deepEqual(result.names.map(n=>[n.speakerID,n.name]),[['s1','Mo']]);
});

test('notes nest sub-bullets under a kept parent and vet topic headings in the meeting language',async()=>{
  const seg={id:'s',text:'Align stopt met HubSpot, het kostte te veel.',start:0,end:3};
  let instructions='';
  const engine=createIntelligence(async(name,schema,text,input)=>{
    if(name==='meeting_notes'){ instructions=text; return {blocks:[
      {id:'lead',kind:'ai',level:0,text:'Align wil een eigen CRM.',sources:[{segmentID:'s',quote:'Align stopt met HubSpot'}]},
      {id:'h1',kind:'heading',level:0,text:'Aanleiding',sources:[]},
      {id:'p',kind:'ai',level:0,text:'Align stopte met HubSpot.',sources:[{segmentID:'s',quote:'Align stopt met HubSpot'}]},
      {id:'c',kind:'ai',level:1,text:'Het kostte te veel.',sources:[{segmentID:'s',quote:'het kostte te veel'}]},
      {id:'h2',kind:'heading',level:0,text:'Klant tekent vrijdag',sources:[]},
      {id:'p2',kind:'ai',level:0,text:'Onbewezen.',sources:[{segmentID:'s',quote:'HubSpot'}]},
      {id:'c2',kind:'ai',level:1,text:'Kind van onbewezen.',sources:[{segmentID:'s',quote:'HubSpot'}]}]}; }
    const ok=new Set(['lead','h1','p','c','c2']);
    return {verdicts:input.items.map(i=>({id:i.id,supported:ok.has(i.id)}))};
  });
  const {blocks}=await engine.enhance({segments:[seg],note:'',language:'Nederlands'});
  assert.match(instructions,/in Nederlands\./);
  assert.deepEqual(blocks.map(b=>[b.kind,b.level??0,b.text]),[
    ['ai',0,'Align wil een eigen CRM.'],['heading',0,'Aanleiding'],['ai',0,'Align stopte met HubSpot.'],['ai',1,'Het kostte te veel.']]);
});

test('an invalid parent takes its sub-bullets, and model IDs cannot borrow the notes heading exemption',async()=>{
  const s={id:'s',text:'Costs rose.',start:0,end:1};
  const blocks=[{id:'p',kind:'ai',level:0,text:'Costs rose.',sources:[{segmentID:'s',quote:'Costs rose.'}]},
    {id:'bad',kind:'ai',level:0,text:'Sales rose.',sources:[]},
    {id:'child',kind:'ai',level:1,text:'Sales detail',sources:[{segmentID:'s',quote:'Costs rose.'}]},
    {id:'chup-from-your-notes-ai',kind:'ai',level:0,text:'Invented claim',sources:[{segmentID:'s',quote:'Costs rose.'}]},
    {id:'chup-from-your-notes-h',kind:'heading',level:0,text:'Deal signed',sources:[]}];
  const e=createIntelligence(async name=>name==='meeting_notes'?{blocks}:{verdicts:[{id:'p',supported:true},{id:'child',supported:true}]});
  const out=(await e.enhance({segments:[s],note:'mine'})).blocks;
  assert.deepEqual(out.map(b=>b.text),['Costs rose.','From your notes','mine']);
  assert.ok(out.every(b=>!('own' in b)));
});
