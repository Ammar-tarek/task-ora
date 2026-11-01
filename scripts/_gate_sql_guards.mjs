// G2 — guards enforce receiving-only write, manager-only assignment to own-dept
// employees, delete lock, and the sender SELECT-only policy.
import { readFileSync } from 'node:fs';
const sql = readFileSync('PROPOSED_task_handoff_field_lock.sql', 'utf8');
const fail = [];

// Receiving-only write: non-receiving writers blocked even for status/progress.
if (!/my_team_id\(\)\s+IS\s+DISTINCT\s+FROM\s+NEW\.team_id/.test(sql))
  fail.push('no receiving-only write guard');

// Definition default-deny keeps only the tracking columns editable.
if (!/-\s*'status'\s*-\s*'completion_percentage'\s*-\s*'updated_at'/.test(sql))
  fail.push('default-deny allow-set changed');

// Assignment: receiving manager only, assignee must belong to receiving team.
if (!/public\.is_manager\(\)\s+AND\s+public\.my_team_id\(\)\s*=\s*v_team/.test(sql))
  fail.push('assignment not gated to receiving manager');
if (!/Assignee must belong to the receiving department/.test(sql))
  fail.push('no assignee-dept check');

// Delete lock + re-transfer handled (delete trigger present).
if (!/trg_guard_transferred_task_delete/.test(sql)) fail.push('no delete lock');

// Sender SELECT-only policy present and read-only (no companion write policy).
if (!/CREATE\s+POLICY\s+tasks_sender_view[\s\S]*?FOR\s+SELECT/.test(sql))
  fail.push('no sender SELECT policy');
if (!/handoff_from_team_id\s*=\s*public\.my_team_id\(\)/.test(sql))
  fail.push('sender policy not scoped to handoff_from_team_id');

// C1=B — assigned employee may move completion only on a transferred task.
if (!/guard_task_employee_fields/.test(sql)) fail.push('employee guard not replaced here');
if (!/v_allow_completion\s+boolean\s*:=\s*\(OLD\.handoff_from_team_id\s+IS\s+NOT\s+NULL\)/.test(sql))
  fail.push('completion carve-out not scoped to transferred task');
if (!/FROM\s+public\.task_assignees[\s\S]*?profile_id\s*=\s*auth\.uid\(\)/.test(sql))
  fail.push('completion carve-out not scoped to the assignee');
if (!/NOT\s+v_allow_completion\s*\n?\s*AND\s+NEW\.completion_percentage\s+IS\s+DISTINCT\s+FROM\s+OLD\.completion_percentage/.test(sql))
  fail.push('completion still unconditionally locked for employees');
// C1=B carve-out also requires caller still belongs to the receiving team.
if (!/FROM\s+public\.profiles\s+WHERE\s+id\s*=\s*auth\.uid\(\)\s+AND\s+team_id\s*=\s*NEW\.team_id/.test(sql))
  fail.push('completion carve-out missing receiving-team membership check');
// Sender SELECT policy covers the whole department (the policy statement itself
// — up to its terminating semicolon — must NOT be gated by is_manager()).
const senderPolicy = (sql.match(/CREATE\s+POLICY\s+tasks_sender_view[\s\S]*?;/) || [''])[0];
if (/is_manager\(\)/.test(senderPolicy))
  fail.push('sender view still gated to managers only (should be whole dept)');

if (fail.length) { console.log('G2_FAIL: ' + fail.join('; ')); process.exit(1); }
console.log('G2_PASS');
