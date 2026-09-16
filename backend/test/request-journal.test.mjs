import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readFileSync,readdirSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {RequestJournal} from '../request-journal.mjs';
function fixture(t){const dir=mkdtempSync(path.join(os.tmpdir(),'chup-journal-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));return new RequestJournal(dir,'test');}
test('completed response survives restart, encrypted on disk, without a second charge',async t=>{
 const journal=fixture(t);let calls=0;
 const work=async()=>{const result=await journal.step('model','backend.responses',async()=>{calls++;return {text:'PRIVATESECRET',usage:{input_tokens:10,output_tokens:3}}});return {...result,usage:journal.usage()};};
 const first=await journal.run('request','fingerprint',work);
 const reopened=new RequestJournal(journal.root,'test');
 assert.deepEqual(await reopened.run('request','fingerprint',()=>{throw Error('Must not call provider');}),first);assert.equal(calls,1);
 for(const file of readdirSync(journal.directory)){assert.equal(readFileSync(path.join(journal.directory,file)).includes(Buffer.from('PRIVATESECRET')),false);}
 assert.equal(first.usage[0].inputTokens,10);
 await assert.rejects(reopened.run('request','different',work),/collision/);
});
test('an unknown provider result blocks automatic replay while preserving prior step usage',async t=>{
 const journal=fixture(t);let second=0;
 const work=async()=>{await journal.step('a','backend.responses',async()=>({usage:{input_tokens:4,output_tokens:1}}));return journal.step('b','backend.responses',async()=>{second++;throw Error('lost connection after accept');});};
 await assert.rejects(journal.run('request','fingerprint',work),/lost connection/);
 const reopened=new RequestJournal(journal.root,'test');
 await assert.rejects(reopened.run('request','fingerprint',()=>reopened.step('a','backend.responses',async()=>{throw Error('cached');}).then(()=>reopened.step('b','backend.responses',async()=>{second++;}))),e=>e.statusCode===409);
 assert.equal(second,1);
});
test('concurrent retries share work and deletion tombstones prevent replay',async t=>{
 const journal=fixture(t);let calls=0;
 const work=()=>journal.step('model','backend.responses',async()=>{calls++;await new Promise(resolve=>setTimeout(resolve,20));return {text:'result'};});
 const [a,b]=await Promise.all([journal.run('same','f',work),journal.run('same','f',work)]);assert.deepEqual(a,b);assert.equal(calls,1);
 journal.forget(['same']);assert.equal(journal.read('same').result,undefined);
 await assert.rejects(journal.run('same','f',work),e=>e.statusCode===410);
});
test('deletion during a provider request cannot recreate cached content',async t=>{
 const journal=fixture(t);let release;
 const task=journal.run('active','f',()=>journal.step('m','backend.responses',()=>new Promise(resolve=>{release=resolve;})));
 journal.forget(['active']);release({text:'PRIVATESECRET'});
 await assert.rejects(task,/deleted/);assert.equal(journal.read('active').status,'forgotten');assert.equal(journal.read('active').steps.length,0);
});
test('missing encryption key fails closed without replacing it or losing completed jobs',async t=>{
 const journal=fixture(t);
 await journal.run('saved','f',async()=>({text:'keep'}));
 const bytes=readFileSync(journal.file('saved'));
 rmSync(path.join(journal.root,'journal.key'));
 assert.throws(()=>new RequestJournal(journal.root,'test'),/key is missing/);
 assert.deepEqual(readFileSync(journal.file('saved')),bytes);
 assert.equal(readdirSync(journal.root).includes('journal.key'),false);
});
