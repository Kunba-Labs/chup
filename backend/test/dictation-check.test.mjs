import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanupPreserves, dictationTokens} from '../contracts.mjs';

test('spoken and written numbers tokenise the same way', () => {
  assert.deepEqual(dictationTokens('about twenty-five, then 2,000 and 15%'), ['about', '25', 'then', '2000', 'and', '15', 'percent']);
  assert.deepEqual(dictationTokens("we don't"), ['we', 'do', 'not']);
});
test('cleanup may delete filler, stutters and an explicitly corrected span', () => {
  const said = 'um can you send the uh budget by friday we cut it by ten percent no actually fifteen percent';
  assert.ok(cleanupPreserves(said, 'Can you send the budget by Friday? We cut it by 15 percent.'));
  assert.ok(cleanupPreserves('call Priya tomorrow', 'Call Priya tomorrow.'));
  assert.ok(cleanupPreserves("um we don't need the the uh report", 'We do not need the report.'));
  assert.ok(cleanupPreserves('send it to marko', 'Send it to Marco.', [{kind: 'spelling', text: 'Marco'}]));
});
test('cleanup must not reword, reorder or drop meaning', () => {
  const said = 'can you send me the updated budget numbers by friday';
  for (const [source, candidate] of [
    ['we cut it by ten percent', 'We cut it by 15 percent.'],
    ['budget is 40 and timeline is 6 weeks', 'The budget is 40.'],
    ['we did not agree to ship', 'We agreed to ship.'],
    ['send it to the team', 'Send it to the team, Marco.'],
    [said, 'Sure, I will send you the updated budget numbers by Friday.'],
    [said, 'You asked whether I can send the updated budget numbers by Friday.'],
    ['send the report to Alice', 'Delete the report to Alice.'],
    ['Alice will call Bob', 'Bob will call Alice.'],
    ['we can ship', 'We will ship.'],
    ['do not send it and delete it', 'Do send it and not delete it.'],
    ['ship if approved', 'Ship.'],
    ['Send the report to Alice and Bob', 'Send the report to Alice.'],
    ['Pay Alice 10 and Bob 20', 'Pay Alice 20 and Bob 10.'],
    ['Send the file to Alice and Bob', 'Send the file to Alice or Bob.'],
    ['No, send the file to Alice and Bob', 'No, send the file to Alice.'],
  ]) assert.ok(!cleanupPreserves(source, candidate), candidate);
});
