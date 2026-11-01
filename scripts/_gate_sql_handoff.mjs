// G1 — handoff_task is DIRECT transfer and the pending-accept RPCs are gone.
import { readFileSync } from 'node:fs';
const sql = readFileSync('PROPOSED_handoff_rpcs.sql', 'utf8');
const fail = [];

// Direct transfer: team_id set to the destination argument (not NULL).
if (!/team_id\s*=\s*p_to_team_id/.test(sql)) fail.push('no direct team_id = p_to_team_id');
// bare team_id (not handoff_*_team_id) must NOT be set to NULL
if (/(?<![_a-z])team_id\s*=\s*NULL/i.test(sql)) fail.push('still sets team_id = NULL (pending model)');

// Pending model removed: no CREATE of accept/reject, and explicit DROPs present.
if (/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.(accept|reject)_handoff/.test(sql))
  fail.push('accept/reject RPC still defined');
if (!/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.accept_handoff/.test(sql))
  fail.push('missing DROP of accept_handoff');
if (!/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.reject_handoff/.test(sql))
  fail.push('missing DROP of reject_handoff');

// Still stamps the sender + clears assignees + authority check intact.
if (!/handoff_from_team_id\s*=\s*v_src/.test(sql)) fail.push('does not stamp sender');
if (!/DELETE\s+FROM\s+public\.task_assignees/.test(sql)) fail.push('does not clear assignees');
if (!/insufficient_privilege/.test(sql)) fail.push('no authority rejection');

if (fail.length) { console.log('G1_FAIL: ' + fail.join('; ')); process.exit(1); }
console.log('G1_PASS');
