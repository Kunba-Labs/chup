import test from 'node:test';
import assert from 'node:assert/strict';
import {speakerReferences} from '../speaker-references.mjs';
function wave(seconds) {
  const data = Buffer.alloc(44 + 48000 * seconds);
  data.write('RIFF'); data.writeUInt32LE(data.length - 8,4); data.write('WAVEfmt ',8);
  data.writeUInt32LE(16,16); data.writeUInt16LE(1,20); data.writeUInt16LE(1,22);
  data.writeUInt32LE(24000,24); data.writeUInt32LE(48000,28); data.writeUInt16LE(2,32);
  data.writeUInt16LE(16,34); data.write('data',36); data.writeUInt32LE(data.length - 44,40);
  return data.toString('base64');
}
test('speaker references have documented 2–10 second bounds and opaque names', () => {
  const result = speakerReferences([{name:'voice_a',audio:wave(2)},{name:'voice_b',audio:wave(10)}]);
  assert.equal(result.length,2); assert.match(result[0].url,/^data:audio\/wav;base64,/);
  assert.throws(()=>speakerReferences([{name:'voice_a',audio:wave(1)}]));
  assert.throws(()=>speakerReferences([{name:'voice_a',audio:wave(11)}]));
  assert.throws(()=>speakerReferences([{name:'Mara',audio:wave(2)}]));
  assert.throws(()=>speakerReferences([{name:'voice_a',audio:'https://elsewhere/audio'}]));
});
test('reference count, duplicate identity and malformed WAV reject before provider call', () => {
  assert.deepEqual(speakerReferences(undefined),[]);
  assert.throws(()=>speakerReferences(Array.from({length:5},(_,i)=>({name:`voice_${i}`,audio:wave(2)}))));
  assert.throws(()=>speakerReferences([{name:'voice_a',audio:wave(2)},{name:'voice_a',audio:wave(2)}]));
  const damaged = Buffer.from(wave(2),'base64'); damaged.writeUInt16LE(2,22);
  assert.throws(()=>speakerReferences([{name:'voice_a',audio:damaged.toString('base64')}]));
});
