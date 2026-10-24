# TaskOra — Department Isolation Audit (end-to-end)

**Scope:** verify, module by module, whether department isolation is enforced at the **database** layer (the only real boundary) or only in Flutter. Read-only DB inspection (`supabase_read_only_user`); no migrations executed. **Isolation is NOT complete** — see confirmed gaps (§B).

**Framing:** By product rule, **Admins/Super Admins are authorized company-wide**, so for them "department" is a *view scope*, not a security boundary. The boundary that must be DB-enforced applies to **managers, employees, and clients**. "Verified" below = checked against actual RLS policy text / function bodies / repository code this session.

---

## A. Isolation matrix

| Module | Primary read path | Enforcement layer | Verified status | Evidence |
|---|---|---|---|---|
| **Tasks — lists** | `TaskRepository._fetchAll` via **RLS client** `_client` | **DB (RLS)** + admin view-filter | **Isolated** for mgr/emp | `task_repository.dart:389` uses `_client`; RLS `manager_team_tasks` (`team_id = my_team_id()`), `tasks_employee_*` (created_by/assignee) |
| **Tasks — open by ID** | `fetchTaskDetail` via `_client` | **DB (RLS)** | **Isolated** | `task_repository.dart:868` all 4 fallbacks use `_client` → cross-dept ID returns null |
| **Subtasks / assignees / comments / approvals** | via `_client` | **DB (RLS)** | **Isolated** | policies `manager_team_task_assignees/comments/approvals` all gate on `manager_task_ids()`; employee/client self-policies |
| **Task attachments / audit log / mentions** | via `_client` | **DB (RLS)** | **Isolated** (same pattern) | policies exist (ALL + SELECT/INSERT); audit log append-only (no UPDATE/DELETE policy) |
| **Dashboard metrics** | `DashboardRepository` via `_admin` | **App-side** (team filter) + per-user notifs | **Scoped, not DB-enforced** | `dashboard_repository.dart` uses `adminClient`; admin branch scoped by `scopeTeamId` (fixed earlier); manager branch filters by team members |
| **Calendar events / attendees** | via `_client` | **DB (RLS)** | **Isolated** | `events` policies: manager = team clients/members, employee = own/attendee, client = own visible; `event_attendees` gated by `manager_event_ids()` |
| **Attendance** | `AttendanceRepository` via **`_admin`** | **App-side only** | ⚠ **Not DB-enforced** | `attendance_repository.dart:290,312` use `_admin`; team scoping only when caller passes `memberIds`/`teamId` |
| **Department finance / revenue** | `FinanceRepository` via **`_admin`** | **App-side only** | ⚠ **Not DB-enforced** | `finance_repository.dart:168,181,194,206` use `_admin`; scoped by `teamId`→memberIds / client ids supplied by caller |
| **Company Expenses** | `_admin`; RLS is admin-only | DB (admin-only) + app | **Separate from dept finance** | `expenses` RLS = single admin policy; no team column — stays company-wide |
| **Penalties** | `PenaltyRepository` via **`_admin`** | **App-side only** | ⚠ **Not DB-enforced**; admin not dept-scoped | `penalty_repository.dart:73,516` use `_admin`; RLS (if it applied) = admin all / manager team |
| **Notifications** | `_client` read (own only) | **DB (RLS)** | **Isolated** (per-recipient) | `notifications` SELECT `recipient_id = auth.uid()` |
| **Analytics / PDF report** | `_admin` (admin/super only) | App (admin-only screens) | Company-wide by design | `super_admin_report_repository.dart:642` `_admin`; gated to super admin in UI |
| **Search (tasks)** | client-side over already-scoped list | inherits task scope | **Isolated** (inherits) | board search filters the RLS-scoped `_tasks` in memory |
| **Custom tables / notes** | `_client` + `get_accessible_table_ids` / `can_access_note` | **DB (RLS + SECURITY DEFINER helpers)** | **Isolated** | helpers gate by team/grant; `custom_*` RLS |
| **Clients** | `_client`; client self = `auth.uid()` | **DB (RLS)** | **Isolated across clients** | `crm_*`/`tasks_client_view` filter `client_id = auth.uid()` (client_profiles.id = auth.users.id) |

---

## B. Confirmed gaps (with exact locations)

### B1 — SECURITY DEFINER views bypass RLS and are REST-reachable **(CRITICAL, confirmed)**
- `tasks_employee_view` — `SELECT … FROM tasks` with **no WHERE**; owner `postgres`; `security_invoker` unset; `has_table_privilege('anon'|'authenticated','SELECT') = true`. → **any authenticated user (and the anon key) can read ALL tasks across every department/client**, bypassing every task RLS policy.
- `admin_tables_overview` — all `custom_tables` metadata, same exposure.
- `client_task_config_view` — all `client_task_visibility` rows (every team↔client config), same exposure.
- (`tasks_client_view`, `crm_client_view` self-filter by `auth.uid()` → safe.)
- **Not referenced anywhere in the Flutter code** (grep clean) → safe to remediate.
- Evidence: `pg_get_viewdef`, `pg_class.reloptions`, `has_table_privilege` (this session).

### B2 — Service-role reads bypass RLS for user-facing data **(confirmed architecture gap)**
Attendance, Finance/Revenue and Penalties read through the **service-role client** (`SupabaseService.adminClient`), so **RLS is not the enforcement layer** — isolation depends solely on the caller passing the correct `teamId`/member ids, and on no alternate caller omitting it.
- `attendance_repository.dart:290, 312, 702, 895`
- `finance_repository.dart:168, 181, 194, 206, 420`
- `penalty_repository.dart:73, 516, 536`
Flutter filtering alone is insufficient per the stated requirement. (The filters that *are* present are correct, but they are not a DB boundary.)

### B3 — `get_profile_by_email(text)` — unauthenticated full-profile lookup **(confirmed)**
SECURITY DEFINER, **no caller check**, **no `SET search_path`**, returns the entire `profiles` row (role, team_id, fcm_token, telegram_chat_id, …) for any email. Enables profile enumeration / PII disclosure by any caller that can reach the RPC.
- DB function `public.get_profile_by_email`; app caller `profile_repository.dart:326` (`fetchByEmail`).

### B4 — `init_client_task_visibility(uuid,uuid,uuid)` — unauthorized write + spoofable actor **(confirmed)**
SECURITY DEFINER, **no caller role check**; writes `configured_by = p_admin_id` from a **client-supplied** argument. A non-admin could create `client_task_visibility` rows for arbitrary team/client pairs and attribute them to any admin.
- DB function `public.init_client_task_visibility`.

### B5 — Super Admin has **no database-level authorization** **(confirmed design gap)**
`user_role` enum has no `super_admin`. The tier is granted **client-side** by a hardcoded email that rewrites `role` in memory:
- `auth_notifier.dart:141-154` (`userEmail == 'ammar@cashback.com'` → `data['role']='super_admin'`).
There is no `is_super_admin` column and no RLS that recognizes it. Not a cross-department leak by itself (super admin is global anyway), but the global tier is unverifiable at the DB and the elevation path is spoofable in the client.

### B6 — Minor / low sensitivity (metadata only, note for completeness)
- `get_accessible_table_ids(p_uid)` and `get_visible_task_columns(p_team_id,p_client_id)` take caller-supplied ids and are SECURITY DEFINER, but return only **table ids / column-key visibility** (no row data). Low impact; tighten opportunistically.

### Not a gap (verified secure)
- `get_reminder_tracking` and `send_manual_attendance_reminders` **do** check `auth.uid()` and lock managers to their own team (supplied `p_team_id` is ignored for managers). ✓

---

## C. Smallest safe implementation + migration plan

**Principle:** make the database the boundary where data is exposed; keep admin/super-admin company-wide; don't break manager/employee flows.

1. **Views (B1)** — `ALTER VIEW … SET (security_invoker = on)` on the three unfiltered views (PG17 supports it), or `DROP` them (unused). Reversible. Impact: non-authorized roles stop reading other departments through them; **no app impact** (unused).
2. **Service-role reads (B2)** — migrate attendance/finance/penalty **reads** from `adminClient` to the RLS `_client`, so RLS enforces scope. Requires first confirming the RLS policies admit the legitimate reads (attendance: ✓ admin/manager-team/employee-own; crm: ✓ admin/manager-clients/client-own; **expenses: admin-only → manager finance "expenses" total would become 0**, a behavior change to decide). This is an **app change gated on regression testing** — proposed, not done blindly.
3. **`get_profile_by_email` (B3)** — add `SET search_path=public`, `REVOKE EXECUTE … FROM anon`, and either restrict to `auth.uid()`'s own row or return minimal columns. Keep the login flow working (the app calls it as an authenticated user).
4. **`init_client_task_visibility` (B4)** — add a caller check (admin, or manager of `p_team_id`) and set `configured_by = auth.uid()`, ignoring the client-supplied id.
5. **Super Admin (B5)** — add `profiles.is_super_admin boolean not null default false` + `is_global_admin()` SECURITY DEFINER helper; replace `get_my_role() = 'admin'` in admin policies with `is_global_admin()`; update `guard_profile_privileged_fields`; seed the intended account; then retire the email hack in `auth_notifier.dart`. `ProfileModel.isSuperAdmin` already reads the flag (forward-compatible).
6. **Refresh on switch (req #7)** — verified: `task_board`, `task_table`, `calendar`, `attendance`, `finance`, `expenses`, and the dashboard attach `TeamFilterNotifier` listeners and reload on department change. Add listeners to any admin screen still missing one (penalties/analytics are company-wide for admins so not a cross-dept stale risk).

**Order:** 1 and 3–4 are low-risk, self-contained DB changes. 5 is the structural one (reversible via boolean, not enum). 2 is the app change with the expense caveat — do after 1/3/4, with the role/department regression matrix.

---

## D. Application-side fixes safe to do now (no DB change)
- The three exposed views are **unused by the app**, so there is no app-side read to remove — the fix is DB-only (§C.1).
- Primary task/calendar/notification/client reads already go through the **RLS client** and are DB-enforced; department **refresh-on-switch** is already wired on the main screens (§C.6).
- Task **creation** is already department-derived and assignees are scoped to the active department (prior milestone: `TaskCreateScope`).
- **No risky app rewrite (B2 service-role→RLS) is applied in this pass** — it changes manager finance/attendance behavior and must be regression-tested (§C.2). Applying it blindly would violate "verify, don't assume."

**Honest conclusion:** manager/employee/client isolation **is** DB-enforced on the core task/calendar/notification/client paths, but **attendance, finance, penalties rely on app-side filtering over a service-role client**, and the **SECURITY DEFINER views + the three RPC/role gaps are live DB-level holes**. Therefore department isolation is **NOT complete** until the §E migrations are approved and applied and B2 is addressed.

---

## E. Proposed migrations (prepared for review — NOT executed)
See `PROPOSED_isolation_migration.sql`. Nothing in it has been run; it needs explicit approval. Each statement is annotated with its gap (B1/B3/B4/B5), its impact, and its rollback.

---

## F. Regression plan (after approval)
Run per role × department boundary: admin (global + per-department view), manager (own team only; denied others), employee (own tasks/attendance only), client (own tasks/finance only; no cross-client). Explicitly test: direct task-ID access across departments; `GET /rest/v1/tasks_employee_view` with the anon key before/after B1; manager finance/attendance after B2; `get_profile_by_email` from anon after B3; super-admin global access after B5.
