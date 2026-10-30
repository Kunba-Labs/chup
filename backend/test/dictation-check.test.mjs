import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanupPreserves, spokenNumbers} from '../contracts.mjs';

test('spoken and written numbers normalise to the same values', () => {
  assert.deepEqual([...spokenNumbers('about twenty-five, then one hundred and five, 2,000 and 15%')], [25, 105, 2000, 15]);
});
test('cleanup may drop filler and apply explicit self-corrections', () => {
  const said = 'um can you send the uh budget by friday we cut it by ten percent no actually fifteen percent';
  assert.ok(cleanupPreserves(said, 'Can you send the budget by Friday? We cut it by 15 percent.'));
  assert.ok(cleanupPreserves('call Priya tomorrow', 'Call Priya tomorrow.'));
});
test('cleanup must not invent or silently drop numbers, change negation, or add names', () => {
  assert.ok(!cleanupPreserves('we cut it by ten percent', 'We cut it by 15 percent.'));
  assert.ok(!cleanupPreserves('budget is 40 and timeline is 6 weeks', 'The budget is 40.'));
  assert.ok(!cleanupPreserves('we did not agree to ship', 'We agreed to ship.'));
  assert.ok(!cleanupPreserves('send it to the team', 'Send it to the team, Marco.'));
  const said = 'can you send me the updated budget numbers by friday';
  assert.ok(!cleanupPreserves(said, 'Sure, I will send you the updated budget numbers by Friday.'));
  assert.ok(!cleanupPreserves('send the report to Alice', 'Delete the report to Alice.'));
  assert.ok(!cleanupPreserves('Alice will call Bob', 'Bob will call Alice.'));
  assert.ok(!cleanupPreserves('Send the report to Alice and Bob', 'Send the report to Alice.'));
  assert.ok(cleanupPreserves("um we don't need the uh report", "We don't need the report."));
  assert.ok(!cleanupPreserves(said, 'You asked whether I can send the updated budget numbers by Friday.'));
  assert.ok(cleanupPreserves('send it to marko', 'Send it to Marco.', [{kind: 'spelling', text: 'Marco'}]));
});
