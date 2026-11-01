# GATES — Task Handoff: Direct Transfer (Option A)

Scope: revise handoff to DIRECT TRANSFER (no accept/reject). Deliverables for
REVIEW only — no migration applied, no SQL run on prod, no deploy/commit/push.

Model (user-approved, 2026-10-31):
- handoff sets tasks.team_id = receiving team immediately; handoff_from_team_id = sender.
- sender dept: SELECT-only (new policy); no edit/assign/delete/re-transfer.
- receiving manager: assigns/reassigns to employees of the receiving team only.
- receiving assigned employee: status + completion only; definition DB-locked.
- global admin: override retained.

## Gates

G1: Handoff RPC is direct-transfer and the pending-accept RPCs are gone.
  CHECK: node scripts/_gate_sql_handoff.mjs
  EXPECT: G1_PASS

G2: Definition-lock + assignee-guard enforce the receiving-only model.
  CHECK: node scripts/_gate_sql_guards.mjs
  EXPECT: G2_PASS

G3: UI permission mirror (task_handoff_lock.dart) matches the direct model.
  CHECK: flutter test test/task_handoff_lock_test.dart
  EXPECT: All tests passed!

G4: All changed Dart analyzes clean (UI finished: accept/reject + waiting list removed).
  CHECK: flutter analyze lib/core/repositories/task_repository.dart lib/features/notifications/notifications_screen.dart lib/features/tasks/task_board_screen.dart lib/features/tasks/task_detail_sheet.dart lib/core/utils/task_handoff_lock.dart test/task_handoff_lock_test.dart
  EXPECT: No issues found!

G5 (manual): Security review + role×state×action test matrix written, every
  requirement row mapped to its DB enforcer. Decisions C1=B (assigned-employee
  completion carve-out) and C2 (sender view-only) recorded as implemented.
  EVIDENCE: HANDOFF_DIRECT_TRANSFER_REVIEW.md

G7: No dangling pending-handoff UI symbols remain in lib/.
  CHECK: node scripts/_gate_ui_cleanup.mjs
  EXPECT: G7_PASS

G6 (manual): Nothing applied/deployed. list_migrations unchanged; git has no new
  applied migration; RPCs/triggers in files are PROPOSED only.
  EVIDENCE: files carry "PROPOSED (NOT APPLIED)" header; no apply_migration call made.

ABANDON: none.

## Evidence (measured 2026-10-31, after sender-dept + C1 team-check + UI gating)

- G1 `node scripts/_gate_sql_handoff.mjs` → `G1_PASS`
- G2 `node scripts/_gate_sql_guards.mjs` → `G2_PASS` (direct transfer, receiving-only,
  assignment+dept, sender whole-dept SELECT, C1=B carve-out + receiving-team check)
- G3 `flutter test test/task_handoff_lock_test.dart` → `All tests passed!` (16/16)
- G4 `flutter analyze` on the 5 changed Dart files + test → `No issues found!`
- G7 `node scripts/_gate_ui_cleanup.mjs` → `G7_PASS` (no acceptHandoff/rejectHandoff/
  _WaitingList/onAcceptHandoff symbols left in lib/)
- Graphify: `graphify update` refreshed graph; impact query shows TaskHandoffLock.canAssign/
  canTrackStatus + _senderReadOnly/_assignmentOnly present, pending-UI symbols gone.
- G6: no apply_migration / no deploy / no commit / no push. Only READ-only SQL (SELECT) run.

UI gating wired (G8, manual): task_detail_sheet — sender=read-only (close only);
receiving manager=assignment-only (definition fields read-only + banner + "Save
Assignment" persisting assignees only); delete/move/increment/archive hidden when
locked. task_board_screen — _moveToDepartment & _deleteTaskRow guarded by
TaskHandoffLock. DB remains authoritative.

SQL integrity (manual): both files re-read from disk — no duplicate function defs,
every trigger DROP-before-CREATE, the one INSERT is 6 cols/6 VALUES, one policy
DROP+CREATE, rollback blocks cover every object incl. C1 restore.
