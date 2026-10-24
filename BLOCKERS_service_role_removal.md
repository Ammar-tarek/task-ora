# TaskOra — Service-role key removal: exact blockers

**Status: the client STILL requires the service-role key. It cannot be removed this turn.**
Every remaining caller needs a backend piece that is *prepared but not deployed/applied*, and
deploying/applying/rotating/committing are all out of scope per the current instructions.
Removing the key now would break live workflows, which is forbidden.

Treat the embedded key as **compromised**. Removing it from source does NOT revoke it — only
rotation does (see BACKEND_SECURITY_PLAN.md §4).

---

## Done this turn (safe, no backend change, RLS-correct, analyze-clean)
Converted from service-role `adminClient` to the authenticated `_client` (RLS enforces scope):

| File | Why safe |
|---|---|
| `analytics_repository.dart` | admin/manager screens; `is_global_admin` / manager RLS covers reads |
| `app_settings_repository.dart` | read = any authenticated; write = admin (app_settings admin-write policy) |
| `team_privileges_repository.dart` | admin ALL + manager read-own policies cover it |
| `user_privileges_repository.dart` | admin ALL + manager-team + read-own policies cover it |
| `super_admin_report_repository.dart` | caller is super admin → `is_global_admin` returns all rows |
| `dashboard_repository.dart` | per-role branches; each read is RLS-correct (admin→all, manager→team, employee→own), all `_safeQuery`-wrapped |

---

## NOT rewired on purpose
`PrivilegedOps`, `supabase/functions/*`, and the `PROPOSED_*.sql` RPCs are **prepared but not
deployed/applied**. Rewiring the privileged callers to them *now* would point live code at
functions that return 404 → the create-user / reset / notify workflows break immediately while
the key is still in the bundle. Correct order (BACKEND_SECURITY_PLAN §3–5): deploy + apply first,
*then* swap callers, *then* delete the key, *then* rotate. So these stay on `adminClient` for now.

---

## HARD BLOCKERS — need `auth.admin.*` (Supabase Admin API). No client/RLS path exists.
Only the prepared Edge Functions can replace these. **Not deployed.**

| File · method | service-role call | Replacement (prepared, not deployed) |
|---|---|---|
| `profile_repository.dart` · `createEmployee` (L125) | `auth.admin.createUser` | Edge Fn `admin-user-ops` (create_user) |
| `profile_repository.dart` · `fetchEmailForUser` (L237) | `auth.admin.getUserById` | `admin-user-ops` (or least-priv RPC) |
| `profile_repository.dart` · `updateEmployee` (L266) | `auth.admin.updateUserById` | `admin-user-ops` (update_user) |
| `client_repository.dart` · `createClientWithAccount` (L162) | `auth.admin.createUser` | `admin-user-ops` (create_user) |
| `client_repository.dart` · `updateClientAccount` (L240) | `auth.admin.updateUserById` | `admin-user-ops` (update_user) |
| `client_repository.dart` · `deleteClient` (L674) | `auth.admin.deleteUser` | `admin-user-ops` (delete_user) |
| `reset_app_repository.dart` · `resetApplicationData` (L90) | `auth.admin.deleteUser` + mass deletes | Edge Fn `admin-reset-app` |
| `notification_repository.dart` · fan-out (L55) | `auth.admin.listUsers` | RPC `notify_action` (server-side fan-out) |

`client_repository.dart` also holds the `adminDb` getter (L78) consumed by feature files; the
whole file must migrate together with the Auth ops above, so its CRM/event reads/writes
(L179–L664) stay on `_adminDb` until then.

## POLICY BLOCKERS — RLS currently denies the needed role. Need prepared-but-unapplied SQL.

| File · method | Problem | Replacement (prepared, not applied) |
|---|---|---|
| `expense_repository.dart` · all (L57–L302) | expenses RLS is **admin-only**; managers/employees would be denied | `PROPOSED_expenses_options.sql` Option B (manager team-scoped policy) |
| `team_repository.dart` · `fetchAllAdmin` (L24) | handoff picker needs OTHER teams, which isolation RLS hides | RPC `list_active_teams()` (`PROPOSED_notify_and_teams.sql`) |
| `task_repository.dart` · archive/countUnarchived (L84–L106, L257–L402) | global cross-team archive | RPC `archive_completed_tasks` (`PROPOSED_privileged_and_pii.sql`) |
| `task_repository.dart` · handoff recipient reads (L474–L769) | reads managers/admins of OTHER teams for notify | `notify_action` RPC (server derives recipients) |

## ENRICHMENT BLOCKERS — cross-department label reads RLS would silently truncate.
Converting blind would return partial data (wrong names/types) with no error — a silent
workflow break. Fold into the owning Edge Fn/RPC, or add a least-priv label RPC.

| File · method | Reads |
|---|---|
| `penalty_repository.dart` · `_fetchProfilesMap`/`_fetchTypesMap`/`fetchTypes` (L81, L94, L291…) | all profiles' names + penalty_types across teams |
| `attendance_repository.dart` · notify enrichment (L122, L497, L573, L658) | employee profile names across teams |
| `finance_repository.dart` · CRM reads + `crm_payments` insert (L145–L428) | cross-client CRM rows |

## FEATURE / SERVICE BLOCKERS — resolve after the repos above.

| File | Refs | Note |
|---|---|---|
| `features/calendar/calendar_screen.dart` | L1868–L2949 (7) | events/rooms reads + rooms insert/delete; uses `ClientRepository.adminDb` path |
| `features/attendance/attendance_screen.dart` | L1224, L2283 | reads via adminClient |
| `features/roles/roles_editor_screen.dart` | L80, L150 | profiles read + role update (admin) |
| `core/services/realtime_service.dart` | L37 | single global realtime channel on the service-role socket; needs per-role channel rework |
| `core/services/apk_update_service.dart` | L111 | app-version read; likely convertible alone but gated by the overall cutover |
| `core/auth/auth_notifier.dart` | L122–L231 (6) | profile/storage reads during auth bootstrap (may run before a usable session) |

---

## What unblocks full removal (the manual steps — not done here)
1. Deploy `admin-user-ops` + `admin-reset-app` Edge Functions; set `SUPABASE_SERVICE_ROLE_KEY`
   in function env only.
2. Apply `PROPOSED_notify_and_teams.sql`, `PROPOSED_handoff_rpcs.sql`,
   `PROPOSED_privileged_and_pii.sql`, and the chosen `PROPOSED_expenses_options.sql` option.
3. Swap the HARD/POLICY/ENRICHMENT callers above to `PrivilegedOps` / the new RPCs / `_client`.
4. Delete `_serviceRoleKey` + `adminClient` from `supabase_service.dart` and the `adminDb` getter.
5. Rebuild; grep built web assets for the secret.
6. **Rotate** the service_role key in Supabase (the only real revocation).
