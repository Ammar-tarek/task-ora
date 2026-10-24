# TaskOra — Write-Path Authorization Audit

Scope: every service-role (`adminClient`) mutation in user-facing modules, its caller, and whether the **database** (not just the Flutter UI) enforces department/permission boundaries. Evidence from repo code + live RLS predicate simulation. **Reads are already RLS-enforced; this covers writes.**

## Key facts
- Most tables' admin + manager policies are `FOR ALL` (USING + WITH CHECK), so **if a write goes through the authenticated `_client`, RLS enforces scope** (manager → own team via WITH CHECK; admin/super → `is_global_admin()`). Writes that go through `adminClient` **bypass** this.
- **Self privilege-escalation is already DB-blocked** by the `guard_profile_privileged_fields` trigger — verified: an employee's self `role`→admin update is rejected, and self `is_super_admin` grant is rejected.
- Predicate proof for penalties: a Montage manager's WITH CHECK yields `own-team employee = true`, `other-team employee = null/false` (reject).

## Matrix
| Mutation (repo.method) | Client | Invokable by | DB-enforced scope? | Cross-dept / escalation today | Classification |
|---|---|---|---|---|---|
| penalty_repository.createPenalty / approvePenalty / rejectPenalty / deletePenalty | **`_client` (fixed)** | admin, manager | **Yes** (manager_team WITH CHECK, is_global_admin) | **No** | ✅ user write — fixed this turn |
| profile_repository.updateRole / updateEmployee / setStatus | adminClient | admin (UI) | No (bypass) | self-escalation **blocked by guard**; admin editing others = legitimate (global) | trusted admin tooling; escalation DB-guarded |
| profile_repository.createUser (`auth.admin.createUser`) | adminClient | admin | n/a | n/a | **trusted server-side (Auth) — must stay service-role** |
| attendance_repository upserts (check-in/out, override, manual) | adminClient | employee(self), manager, admin | No (bypass; RLS self/team/admin ALL exists) | a manager/admin *could* write another dept's attendance by direct id (not via UI) | user write → **GAP (P2): route to `_client`** |
| expense_repository insert / update / delete | adminClient | admin (UI) | No (bypass; expenses RLS admin-only) | expenses are admin-only; via `_client` a manager write would be correctly rejected | user write → **GAP (P2): route to `_client`** |
| task_repository create / update / delete | mixed | admin, manager, employee | partial | manager/employee could alter out-of-scope task by direct id | user write → **GAP (P3): route to `_client`** |
| task_repository.handoffTask | adminClient | manager | No | manager could hand off a task they don't own | **GAP (P3) — needs care:** handoff sets `team_id=NULL`, which fails the manager WITH CHECK (`team_id=my_team_id`). Needs a dedicated handoff policy OR a validated server-side RPC (verify caller owns `fromTeamId`). |
| task_repository.archiveCompletedTasks | adminClient | super admin (UI) | No | super-admin-only bulk op | privileged op; validate super_admin server-side |
| client_repository.createClientWithAccount (`auth.admin`) | adminClient | admin | n/a | n/a | **trusted server-side (Auth) — must stay** |
| client_repository update / link | adminClient | admin | No | admin global = legit | updates → GAP (P3): route to `_client` |
| notification_repository fan-out insert | adminClient | system / DB triggers | n/a | n/a | **trusted server-side delivery — must stay** |
| reset_app_repository.* (delete/reset) | adminClient | super admin (UI) | No (UI-gated only) | a non-super admin calling it would succeed server-side | **privileged op — validate super_admin server-side (not DB-gated today)** |

## Confirmed gaps (prioritized)
1. **(FIXED)** Penalty writes bypassed the manager-team WITH CHECK → now `_client`, DB-enforced.
2. **(P2)** Attendance & expense writes still service-role — DB does not reject cross-department/unauthorized writes; only the (now RLS-scoped) UI pickers constrain inputs. Fix = route through `_client`; the existing ALL policies enforce. Attendance needs careful check-in-flow testing (auto check-in runs as the employee → employee-self policy permits).
3. **(P3)** Task writes, esp. **handoffTask** — routing to `_client` requires a handoff-aware policy (the manager WITH CHECK rejects `team_id=NULL`), or a narrowly-scoped server-side RPC that verifies the caller owns the source team. Do **not** trust a client-supplied team id.
4. **(Hardening)** `reset_app` and `archiveCompletedTasks` are super-admin-only in the UI but not DB-gated — a server-side caller check (`is_super_admin`) is advisable.
5. **Trusted / must stay service-role:** Auth user creation and notification fan-out.

## No new DB migration required for P2
The `attendance`, `expenses`, `penalties`, `tasks` ALL policies already carry WITH CHECK, so P2 is an **application change** (route writes to `_client`). P3 handoff is the only item that may need a new policy/RPC.

## Not claiming complete isolation
Reads: fully RLS-enforced (verified). Writes: penalties fixed & verified; attendance/expense/task/client writes remain service-role (gaps above). Isolation is complete only once P2/P3 writes are converted and regression-tested in the running app.
