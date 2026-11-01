# Task Handoff — Direct Transfer (Option A): Security Review & Test Matrix

Status: **PROPOSED — nothing applied, deployed, committed, or run against prod.**
Date: 2026-10-31. For review before any apply.

Files in this change set:
- `PROPOSED_handoff_rpcs.sql` — rewritten: direct-transfer `handoff_task`; `accept_handoff`/`reject_handoff` dropped.
- `PROPOSED_task_handoff_field_lock.sql` — rewritten: definition lock + **receiving-only write** + **manager-only assignment to own-dept employees** + delete lock + **sender SELECT-only policy**.
- `lib/core/utils/task_handoff_lock.dart` + `test/task_handoff_lock_test.dart` — UI permission mirror for the direct model (+`canAssign`, receiving-only `canTrackStatus`).

---

## 1. Role mapping (as approved)

| Concept in the workflow | Actual DB identity |
|---|---|
| Global Admin (override) | `is_global_admin()` = `role='admin' OR is_super_admin` |
| Receiving dept Manager | `is_manager()` AND `my_team_id() = tasks.team_id` |
| Receiving employee | assignee of the task whose `profiles.team_id = tasks.team_id` |
| Sending dept | team = `tasks.handoff_from_team_id` |

**Verified:** there is NO department-scoped "admin" role in this schema; `admin` is global. No new role introduced (per instruction).

---

## 2. Requirement → DB enforcer (verified mapping)

| # | Requirement | Enforced by |
|---|---|---|
| 1 | Handoff immediately transfers ownership | `handoff_task`: `UPDATE tasks SET team_id = p_to_team_id, handoff_from_team_id = v_src` |
| 2 | Sender loses all edit; view/track only | §1 receiving-only write guard (`my_team_id() <> NEW.team_id` → reject) + no sender UPDATE/DELETE policy; `tasks_sender_view` grants SELECT only |
| 3 | Visible to receiving Admin/Manager | receiving manager sees via existing `manager_team_tasks` (team_id = my_team_id); global admin via `tasks_admin_all` |
| 4 | Receiving Manager assigns/reassigns to own-dept employees | `guard_transferred_task_assignees`: manager-of-receiving-team only; assignee must have `profiles.team_id = tasks.team_id`; RLS `manager_team_task_assignees` also gates on team ownership |
| 5 | Receiving employee updates status + completion only | definition default-deny (allow `{status, completion_percentage, updated_at}`) **— see Conflict C1 for completion_percentage** |
| 6 | Receiving Manager cannot edit definition | same default-deny lock applies to the manager too (only admin overrides) |
| 7 | Employees cannot assign/reassign/transfer | `guard_transferred_task_assignees` requires `is_manager()`; `handoff_task` requires manager/admin |
| 8 | Sender cannot edit/reassign after handoff | §1 receiving-only guard + assignee guard both reject a sender-team writer |
| 9 | No dept re-transfer / delete; admin override | `handoff_task` blocks re-transfer unless admin; `guard_transferred_task_delete` blocks dept delete; admin/service override throughout |

---

## 3. Role × action matrix on a TRANSFERRED task (src→dst)

Legend: ✅ allowed · ⛔ rejected (`insufficient_privilege`).

| Actor | SELECT | status/progress | definition field | assign own-dept emp | assign other-dept emp | delete | re-transfer |
|---|---|---|---|---|---|---|---|
| Sending manager (src) | ✅ (`tasks_sender_view`) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| Sending creator employee | ✅ (created_by) | ⛔ (receiving-only) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| Receiving manager (dst) | ✅ | ✅ | ⛔ (locked) | ✅ | ⛔ (dept) | ⛔ | ⛔ |
| Receiving assigned employee | ✅ | ✅ status; completion = **C1** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| Other-team manager | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| Global admin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

On a NORMAL (never-transferred) task every guard early-returns — behavior unchanged.

---

## 4. Decisions (RESOLVED and implemented)

**C1 = B — implemented.** Only an employee **assigned to a transferred task** may
change `completion_percentage`. `guard_task_employee_fields` is replaced in
field-lock §5: the completion clause is skipped only when
`OLD.handoff_from_team_id IS NOT NULL` AND the caller has a `task_assignees` row
for the task. Every other employee, and every non-transferred task, is unchanged
(completion still locked). This is the ONE existing trigger this change modifies.

**C2 = confirmed — implemented.** The sending department, including the original
creator, is view-only after handoff. field-lock §1 rejects any write whose
`my_team_id() <> NEW.team_id` on a transferred task, closing the `created_by`
RLS write path. The sender manager keeps SELECT via `tasks_sender_view`; the
sender creator keeps SELECT via the existing `created_by` SELECT clause.

**C3 — inert old policy.** `tasks_manager_waiting` (pending model) now matches
nothing (handoff_to_team_id stays NULL). Left in place as harmless; optional
`DROP` provided commented-out (a live change — separate approval).

---

## 5. UI implementation (DONE — analyzes clean)

- `lib/core/repositories/task_repository.dart`: `handoffTask` calls the now-direct
  RPC (unchanged signature). `acceptHandoff`/`rejectHandoff` **removed**. Manager
  fetch `.or(...)` now `team_id.eq OR handoff_from_team_id.eq` so the sender keeps
  SELECT-only visibility of tasks it sent.
- `lib/features/notifications/notifications_screen.dart`: accept/reject methods +
  buttons **removed**; `_NotifCard` handoff params dropped; handoff notification is
  informational (tap opens the task). Unused import removed.
- `lib/features/tasks/task_board_screen.dart`: `_WaitingList` widget, `_waiting`
  getter, `_openWaitingDetail`, `_acceptHandoff`, `_rejectHandoff`, and `_teamName`
  **removed**; `_buildBody` no longer renders a waiting list. Transferred tasks
  land on the receiving team's board directly.
- `lib/features/tasks/task_detail_sheet.dart`: `onAcceptHandoff`/`onRejectHandoff`
  params + Accept/Reject Handoff buttons **removed**.
- `lib/core/utils/task_handoff_lock.dart` (+ test): direct-model mirror — no
  "awaiting" state; `canEditDefinition`, receiving-only `canTrackStatus`,
  `canAssign` (receiving manager), `canDelete`, `canHandoff`.

Optional (not required; DB already enforces): gate the detail-sheet edit/assign
controls with `TaskHandoffLock` for a tighter UX. Left as polish.

---

## 6. Migration execution order (AWAITING your per-file confirmation)

1. **`PROPOSED_handoff_rpcs.sql`** FIRST — defines `handoff_task` (direct) and
   drops `accept_handoff`/`reject_handoff`. Its RPC sets the `app.task_handoff`
   GUC the field-lock triggers read.
2. **`PROPOSED_task_handoff_field_lock.sql`** SECOND — definition lock +
   receiving-only write, assignment guard, delete lock, `tasks_sender_view`
   policy, and the C1=B `guard_task_employee_fields` replacement.

Then: deploy the Flutter build, and run the per-SQL `-- VALIDATION` blocks on a
branch with role-based test accounts (sender manager, receiving manager,
receiving assigned employee, receiving non-assigned employee, global admin).

Nothing in steps 1–2 is run until you confirm each file explicitly.

### Static verification of the 5 pre-apply items you asked for
- **RPC authorization:** `handoff_task` requires `is_global_admin()` OR
  (`is_manager()` AND `my_team_id() = v_src`); re-transfer blocked unless admin;
  `EXECUTE` revoked from PUBLIC/anon, granted to `authenticated` only. ✔
- **Assignment validation:** receiving-manager-only + assignee must have
  `profiles.team_id = tasks.team_id`; RLS `manager_team_task_assignees`
  (`manager_task_ids()` = `team_id = my_team_id()`) also gates it. ✔
- **RLS:** sender write removed (team no longer matches `manager_team_tasks`);
  `tasks_sender_view` grants SELECT only; receiving manager via
  `manager_team_tasks`; admin via `tasks_admin_all`. ✔
- **Employee-trigger interaction:** both `trg_guard_task_employee_fields` and
  `trg_guard_transferred_task_definition` are BEFORE UPDATE and must BOTH pass;
  neither is weakened except the scoped C1=B completion carve-out. ✔
- **Rollback:** each file has a reversible rollback block; C1 rollback = re-run
  the pre-C1 `guard_task_employee_fields` from `PROPOSED_task_assignment_response.sql`. ✔

---

## 7. Verification evidence (this session)

| Gate | Check | Result |
|---|---|---|
| G1 | `node scripts/_gate_sql_handoff.mjs` | **G1_PASS** (direct transfer; accept/reject dropped) |
| G2 | `node scripts/_gate_sql_guards.mjs` | **G2_PASS** (receiving-only + assignment + sender policy + C1=B carve-out) |
| G3 | `flutter test test/task_handoff_lock_test.dart` | **All tests passed!** (16/16) |
| G4 | `flutter analyze` (all 5 changed Dart + test) | **No issues found!** |
| G5 | this document | written |
| G6 | no apply/deploy/commit | confirmed — only PROPOSED files + Dart written |
| G7 | `node scripts/_gate_ui_cleanup.mjs` | **G7_PASS** (no dangling accept/reject/_WaitingList symbols) |

Graphify: graph refreshed (`graphify update`, 3877 nodes); handoff impact query
confirms `TaskHandoffLock`/`canAssign` present and the removed pending-UI symbols
gone. SQL correctness is argued + statically checked, not executed (no prod run).

---

## 9. Final revision (2026-10-31, pre-Migration-1 corrections)

**(1) Sender visibility = WHOLE sending department.** `tasks_sender_view` is no
longer gated by `is_manager()`; it now grants SELECT to every staff member whose
`my_team_id() = handoff_from_team_id` (manager AND employees). Still SELECT-only
(no companion write/assign/delete policy). Verified: field-lock §4.

**(2) C1=B carve-out strengthened.** `guard_task_employee_fields` now allows an
employee to change `completion_percentage` only when ALL hold: task transferred
(`OLD.handoff_from_team_id IS NOT NULL`), caller is an assignee
(`task_assignees`), AND caller still belongs to the receiving team
(`profiles.team_id = NEW.team_id`). Normal tasks and unassigned employees
unchanged. Verified: field-lock §5.

**(3) `_fetchAll` query (repo).** One OR condition, single `.or()` call:
`.or('team_id.eq.$teamId,handoff_from_team_id.eq.$teamId')`. PostgREST treats one
`.or('a,b')` as `a OR b`; no chained `.or()` (which would AND and drop a branch).
Receiving team sees incoming (team_id=theirs); sending team sees outgoing
(handoff_from=theirs). Verified by reading `task_repository.dart` `_fetchAll`.

**(4) UI gating wired (NOT optional) — `flutter analyze` clean.**
- `task_detail_sheet.dart`: sending dept / non-receiving viewer → read-only body,
  Close-only actions, `_save` no-ops. Receiving manager on a transferred task →
  assignment-only: title/description read-only, a lock banner, delete/move/
  increment/archive hidden, Save labelled "Save Assignment" and persists ONLY the
  assignee set (`_saveAssignmentOnly`, never the definition). Receiving assigned
  employee → status/progress (DB C1=B allows completion). Global admin → full.
- `task_board_screen.dart`: `_moveToDepartment` and `_deleteTaskRow` guarded by
  `TaskHandoffLock.canHandoff` / `canDelete` (admin override).
- DB remains the authoritative boundary; UI only hides/disables what DB rejects.

**SQL integrity (read from disk):** no duplicate function definitions; every
trigger `DROP ... IF EXISTS` before `CREATE`; the single `INSERT` (handoff audit)
is 6 columns / 6 VALUES; one policy DROP+CREATE; rollback blocks cover every
object, incl. restoring the pre-C1 `guard_task_employee_fields`.

**Gates (measured):** G1 PASS · G2 PASS · G3 16/16 · G4 No issues · G7 PASS ·
G6 nothing applied. See `GATES.md` → Evidence.

---

## 8. Assumptions (distinct from verified)

- "Receiving department's Admin" = receiving manager + global admin (no dept-admin role). **Verified** no dept-admin exists.
- Sender employees other than the creator do not need visibility (only the creator keeps it via created_by, plus the sending manager via the new policy). **Assumption** — say if sender employees should all see it.
- `teams.is_active`, `profiles.team_id`, all `handoff_*` columns **exist** (verified live).
- Assignee-belongs-to-dept is enforced only on transferred tasks (not retrofitted to normal tasks). **Assumption** to avoid changing normal-task behavior.
