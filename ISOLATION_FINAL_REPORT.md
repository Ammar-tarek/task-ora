# TaskOra — Department Isolation: Status

## 🚨 TOP BLOCKER — service_role key is in the Flutter client
`lib/core/services/supabase_service.dart:12` hardcodes the **service_role** JWT and builds `adminClient` with it. That key **bypasses all RLS** and ships in `build/web` and the APK. Anyone who extracts it can read/write/delete **every department's data** — which defeats every RLS/handoff/attendance fix below. **Isolation CANNOT be called complete while this key is in the client.**

Fix (not code-only-quick; needs your action + backend):
1. **Rotate** the leaked service_role key in Supabase now (the one in the repo is burned).
2. Move the trusted service-role ops (Auth user create, notification fan-out, reset/archive) to **Supabase Edge Functions** that check the caller server-side.
3. Remove `_serviceRoleKey` + `adminClient` from the Flutter app; repositories call the Edge Functions or `_client`.
This is an architecture task — I did not do it autonomously (big, needs your call). Everything below is defense-in-depth that still matters once the key is gone.

## Code changed this pass (not committed)
- `task_repository.dart` — handoff/accept/reject/bulk-handoff → authenticated RPC (`handoff_task`/`accept_handoff`/`reject_handoff`); no service-role fallback; fails safe until RPC deployed.
- `attendance_repository.dart` — ALL attendance writes AND per-employee reads → `_client` (self/team/admin via RLS). Only profiles-enrichment reads stay service-role.
- `client_repository.dart` — `fetchClientById` → `_client` (client self / manager team / admin).
(Prior passes: penalties read+write, finance/expense/dashboard reads, task single+bulk writes, super-admin flag, workspace nav — all `_client`/RLS.)

## Prepared SQL — NOT applied (you must approve; I did not apply any this pass)
1. `PROPOSED_handoff_rpcs.sql` — 3 hardened RPCs (auth.uid check, source-team authority, active dest, FOR UPDATE lock, replay guard, audit old/new, authenticated-only). **Handoff is down until this is deployed.**
2. `PROPOSED_privileged_and_pii.sql` — (A) `archive_completed_tasks()` + `assert_super_admin()` super-admin DB gate; (B) `get_profile_by_email` least-privilege (id/role/status/full_name/team_id; needs DROP, app stays compatible).
3. `PROPOSED_expenses_options.sql` — Option A (admin-only) vs Option B (manager team-scoped). **Recommend B** (product gates expenses to managers via can_manage_expenses; B keeps it, no company-wide; tradeoff: managers then see their team's expenses). Decision needed.

Note: a full DB RPC for `reset_app` is NOT possible — it deletes **Auth users** (`auth.admin.deleteUser`), which only the service role can do. Reset must become an Edge Function (ties to the top blocker). `assert_super_admin()` is prepared for the guard.

## Migrations already applied (verified earlier; not re-applied)
`isolation_b1_security_invoker_views`, `isolation_b5_core_superadmin`, `isolation_b3_b4_rpc_hardening`, `isolation_b3_revoke_anon_profile_email`, `isolation_b5_policies_global_admin`, `penalties_employee_self_read`.

## Service-role audit (remaining `adminClient` usage)
| Path | Class | Why it stays / action |
|---|---|---|
| `SupabaseService.adminClient` key itself | **UNRESOLVED (critical)** | key in client → full bypass; must move to backend + rotate |
| notification fan-out | trusted server-side | delivery; move to Edge Fn with the key |
| Auth user create (profile/client) | trusted server-side | only service role can create auth users; move to Edge Fn |
| task archiveCompletedTasks / archiveTasksByFilter / countUnarchived | user-triggered write (super-admin) | gate pending (`archive_completed_tasks` RPC) |
| reset_app.* | user-triggered write (super-admin) | must become guarded Edge Fn |
| penalty/attendance/finance enrichment (names, team_id, client-type) | trusted read (labels only) | attached to already-authorized rows; fine |
| profile updateRole/updateEmployee/setStatus | user-triggered write (admin tooling) | self-escalation blocked by guard trigger; admin-of-others legit; move to Edge Fn with the key |
| super_admin_report | trusted read (super-admin screen) | company-wide by design |

## Authorization matrix (DB-enforced for authenticated `_client`; **moot if key leaks**)
| Resource | Super Admin | Admin | Manager | Employee | Client |
|---|---|---|---|---|---|
| Tasks R/W (single+bulk) | all | all | own team | own/assigned | own via view |
| Handoff | all | all | source-team (RPC ⏳) | — | — |
| Attendance R/W | all | all | own team | self only | — |
| Expenses | all | all | decision (A/B) | none | none |
| Penalties | all | all | own team | own only | none |
| Clients | all | all | team clients | — | self |
| Privileged fields | guarded | guarded | no self-set | no self-set | — |
| reset/global archive | yes (gate ⏳) | no | no | no | no |

## Tests / build
- `dart analyze lib`: clean except 1 pre-existing warning (`task_board_screen.dart:414`).
- `flutter test --no-pub`: 50/50 (automated unit).
- `flutter build web --no-pub`: success.
- RLS simulations (read-only, done): role read/write scope, handoff predicate, penalty own-only, anon views = 0, attendance self/team.
- **Real in-app smoke tests NOT yet done:** attendance check-in/out + manual/override; handoff/accept/reject (after RPC deploy); sign-in + team-member email search.

## Decisions / approvals needed (grouped)
1. **Service_role key** (CRITICAL): rotate it + approve moving trusted ops to Edge Functions. Until then, isolation is bypassable.
2. **Apply `PROPOSED_handoff_rpcs.sql`** → re-enable handoff; then me wire-verify.
3. **Expenses: Option A or B** (recommend B).
4. **Apply `PROPOSED_privileged_and_pii.sql` A + B** (archive gate; profile-email least-priv).
5. Run the in-app smoke tests above.

Isolation is NOT complete: the embedded service_role key is a full bypass, handoff needs its RPC deployed, expenses write awaits a decision, and attendance/handoff need the in-app smoke test.
