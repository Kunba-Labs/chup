import test from 'node:test';
import assert from 'node:assert/strict';
import {validateSummary,validateSegments,chunkSegments,liveStart,transcriptionStart} from '../contracts.mjs';
const segment = {id:'m1:s1',meetingID:'m1',text:'We did not agree to ship Friday.',start:2,end:4,provisional:false};
test('foreign or fabricated citations fail',()=>{
 assert.throws(()=>validateSummary({items:[{id:'x',text:'Ship Friday',sources:[{segmentID:'m2:s1',quote:'ship Friday'}]}]},[segment]));
 assert.throws(()=>validateSummary({items:[{id:'x',text:'Ship Friday',sources:[{segmentID:segment.id,quote:'We agreed'}]}]},[segment]));
});
test('empty evidence fails',()=>assert.throws(()=>validateSummary({items:[{id:'x',text:'Anything',sources:[]}]},[segment])));
test('a decision date cannot silently become an action deadline or completion status',()=>{
 const item={id:'decision',category:'decision',text:segment.text,owner:null,dueDate:null,status:'unknown',sources:[{segmentID:segment.id,quote:segment.text}]};
 assert.equal(validateSummary({items:[item]},[segment]).items.length,1);
 for(const change of [{dueDate:'Friday'},{owner:'the team'},{status:'done'}])assert.throws(()=>validateSummary({items:[{...item,...change}]},[segment]),/Only action items/);
});
test('provisional transcript excluded from final facts',()=>assert.equal(validateSegments([{...segment,provisional:true}]).length,0));
test('malformed timings and duplicate source identities rejected',()=>{
 assert.throws(()=>validateSegments([{...segment,start:-1}])); assert.throws(()=>validateSegments([segment,segment]));
});
test('long transcript chunks retain identities and order',()=>{
 const all = Array.from({length:500},(_,i)=>({...segment,id:`s${i}`,text:'x'.repeat(1000)}));
 const chunks = chunkSegments(all,5000); assert.ok(chunks.length>100); assert.deepEqual(chunks.flat(),all);
});
test('Live conversation and live transcription never share their event protocol',()=>{
 assert.equal(liveStart().type,'session.start'); assert.equal(liveStart().session.model,'gpt-live-1'); assert.equal(liveStart().session.delegation.type,'client');
 assert.equal(transcriptionStart().type,'session.update'); assert.equal(transcriptionStart().session.audio.input.transcription.model,'gpt-live-transcribe');
});

test('conversation context is bounded data without role or tool authority',async()=>{
 const {validateHistory}=await import('../contracts.mjs');
 assert.deepEqual(validateHistory([{question:'What did we decide?',answer:'No date yet.',role:'system',tool:'delete'}]),[{question:'What did we decide?',answer:'No date yet.'}]);
 assert.throws(()=>validateHistory(Array(9).fill({question:'q',answer:'a'})));
 assert.throws(()=>validateHistory([{question:'q',answer:'x'.repeat(4001)}]));
});
