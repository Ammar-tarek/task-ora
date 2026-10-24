# TaskOra — Remove client service-role key (plan; nothing deployed)

The service_role key is embedded in `lib/core/services/supabase_service.dart` and used by `SupabaseService.adminClient`. It bypasses all RLS and ships in every build. Treat it as **compromised**. This plan moves every privileged op to a trusted boundary, then the key leaves the client. **No key removed, no function deployed, no key rotated here** — those are your manual steps (§4).

## 0. Why not just delete the key now
Removing `adminClient` today breaks: user create/delete, role/status edits, app-initiated notifications, reset, global archive, the handoff/notify enrichment, and the manager handoff destination picker. Per the "don't silently break prod" rule, the key stays until the replacement below is deployed.

## 1. adminClient classification → target
| Caller(s) | Op class | Target |
|---|---|---|
| ProfileRepository.createUser / updateEmployee / updateRole / setStatus / fetchEmail; ClientRepository.createClientWithAccount | Auth user create/update + profile write | **Edge Fn `admin-user-ops`** (prepared) |
| ResetAppRepository.resetApplicationData (+ `auth.admin.deleteUser`) | reset/destructive + auth delete | **Edge Fn `admin-reset-app`** (super-admin; spec §2) |
| TaskRepository.archiveCompletedTasks / archiveTasksByFilter / countUnarchived | global archive (no auth delete) | **RPC `archive_completed_tasks`** (prepared in PROPOSED_privileged_and_pii.sql) |
| NotificationRepository.notifyAction / createNotification / fan-out | app-initiated notification insert | **Edge Fn `notify`** (spec §2) — or a SECURITY DEFINER `create_notification` RPC that validates recipients |
| TeamRepository.fetchAllAdmin / fetchMembersAdmin (handoff picker needs other teams) | read other teams/members | **RPC `list_active_teams()`** (names/ids only; spec §2) + members via existing RLS |
| Penalty/attendance/finance enrichment (names, team_id, client_type) | trusted label reads | fold into the owning Edge Fn, or convert to `_client` where RLS allows |
| SuperAdminReportRepository.* | super-admin company-wide report | **Edge Fn `admin-report`** (super-admin) or run report via `_client` as the super admin |
| auth_notifier adminClient profile-fetch fallback | read own profile | switch to `_client` (RLS `Users read own profile`) |
| auth_notifier `ammar@cashback.com` role rewrite | client-side elevation hack | delete — superseded by DB `is_super_admin` flag |

## 2. Edge Functions to create (prepared / to spec)
- **`admin-user-ops`** — DONE (`supabase/functions/admin-user-ops/index.ts`). Global-admin only; super-admin required to grant super_admin; create/delete/update auth user + profile.
- **`_shared/auth.ts`** — DONE. JWT → caller, role/super from DB, `requireGlobalAdmin` / `requireSuperAdmin`.
- **`admin-reset-app`** — super-admin only (`requireSuperAdmin`); run the existing delete order server-side, then `auth.admin.deleteUser` for non-super profiles. Keep the exact table order from ResetAppRepository. (Not written — destructive; write + review carefully before deploy.)
- **`notify`** — authenticated; insert notifications for a validated recipient set (e.g. task assignees / team of a task the caller can see). Prevents arbitrary-recipient spam.
- **`list_active_teams()`** — may be a plain SECURITY DEFINER RPC: `SELECT id, name, department FROM teams WHERE is_active` for any authenticated user (team names are not department-sensitive data; needed for the handoff destination picker).

## 3. Client swap (after functions deployed)
- Replace `adminClient.auth.admin.*` + privileged writes with `SupabaseService.client.functions.invoke('admin-user-ops', body: {...})` etc. The user JWT is attached automatically.
- Delete `_serviceRoleKey` and `adminClient` from `supabase_service.dart`. Keep only the anon `client`.
- Ordinary reads/writes already use `_client` (this isolation work).
- Handoff already uses RPCs; archive → `archive_completed_tasks` RPC; reset → `admin-reset-app`.

## 4. Manual steps (you — not done here)
1. **Rotate** the service_role key: Supabase → Settings → API → roll `service_role`. The embedded key is burned (it is in published builds + git history; removing from source does NOT revoke it). Rotation is the only revocation.
2. Set function env: `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<new key>` (Supabase injects SUPABASE_URL/ANON automatically). The new key goes ONLY into function env, never the client.
3. `supabase functions deploy admin-user-ops` (and the others once written).
4. Apply the prepared SQL (handoff RPCs, privileged+pii, chosen expense option).
5. Ship the client swap (§3); rebuild; verify.
6. Also rotate the **anon** key only if you want (anon is meant to be public; lower priority).

## 5. Breaks until the replacement is deployed
Nothing breaks now (key still present). After you delete the client key but BEFORE functions deploy, these fail: create/edit user, reset, global archive, app-initiated notifications, handoff destination picker. Deploy functions first, then remove the key — do the §4 order.
