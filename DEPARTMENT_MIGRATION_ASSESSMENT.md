# TaskOra — Department Architecture: Migration & Security Assessment

**Mode:** Read-only inspection. No INSERT/UPDATE/DELETE/DDL was run; the database connection is the role `supabase_read_only_user` (which has no write capability). No application files were modified. This document is the deliverable only — **no implementation has been performed. Awaiting approval.**

**Date:** 2026-10-17 · **DB:** PostgreSQL 17.6 · **Schema:** `public` (50 tables)

---

## 0. ⚠️ Correction to the prior assessment

The earlier inspection reported **"zero declared foreign-key constraints."** That was a **false negative** and must be retracted.

- Root cause: the read-only role returns **empty results from `information_schema`** constraint/trigger views (`table_constraints`, `key_column_usage`, `triggers`), but returns data from `information_schema.columns`. Querying `pg_catalog` directly (which the role *can* read) shows the real picture.
- **Confirmed via `pg_catalog`:** the database has **50 PRIMARY KEY, 108 FOREIGN KEY, 25 UNIQUE, and 16 CHECK constraints**, plus 61 triggers and 50 functions. Referential integrity **is** enforced at the database level.

Everything below is derived from `pg_catalog` / `pg_policies` / `pg_get_*def()` and from reading the Flutter source. Where a fact could not be verified, it is labeled **ASSUMPTION** or **UNVERIFIED**.

---

## 1. Confirmed facts vs. assumptions (executive summary)

### Confirmed facts
1. **Teams already model departments.** `teams.department` (text) is populated for Marketing, Montage, Video Production and `NULL` for `Admins` and `Sales`. One team ≈ one department today.
2. **Tasks are already department-attributable.** All **256/256 tasks have a non-null `team_id`** (`idx_tasks_team` exists). No backfill needed to attribute existing tasks to a department.
3. **A user belongs to exactly one team.** `profiles.team_id` is a single nullable uuid (`idx_profiles_team_id`). Managers/employees are scoped to one team; clients have `team_id = NULL` (all 11 clients), admins are global.
4. **Manager scoping is enforced in RLS by team membership**, via SECURITY DEFINER helpers `my_team_id()`, `manager_task_ids()`, `manager_member_ids()`, `manager_client_ids()`, `manager_event_ids()`, `manager_board_ids()` — *not* by the privilege flags.
5. **Expenses are already company-wide and admin-only** in RLS (single `admin` policy; no team column; no manager policy).
6. **`super_admin` does not exist in the database.** The `user_role` enum is exactly `(admin, employee, client, manager)`. The app references `super_admin` but it was never added.
7. **Three SECURITY DEFINER views bypass RLS and are REST-reachable** by `anon`/`authenticated` with no row filter (details in §4.4). This is a confirmed cross-department/cross-client exposure path.
8. **353 notifications reference deleted tasks** (polymorphic `reference_id`, intentionally no FK). Benign log dangling, not corruption of an enforced relationship.

### Assumptions (require product confirmation before implementation)
- **A1:** "Department" = one `teams` row. The redesign's 5 departments (Marketing, Montage, Production, Sales, Studio) map to teams; `Video Production` ≈ `Production`, and `Studio` has **no team yet**. *Unverified whether `Video Production` should be renamed `Production` or kept distinct.*
- **A2:** Super Admin and Admin are both **global** (all departments). The only Super-Admin-specific powers (app reset, company report, archiving) are **app-gated**, not DB-gated.
- **A3:** A client may legitimately be served by more than one department (one client currently spans two teams). Needs a product decision (see §7.4).
- **A4:** Employees do **not** need cross-department membership (single `team_id` is sufficient).

---

## 2. How roles, membership & permissions are represented

| Concept | Where it lives | Notes |
|---|---|---|
| Role | `profiles.role` → enum `user_role (admin, employee, client, manager)` | **No `super_admin`.** `get_my_role()` reads this. |
| Department / team membership | `profiles.team_id` → `teams.id` (FK `ON DELETE SET NULL`) | One team per user. `my_team_id()` returns it. |
| Team identity | `teams (id, name UNIQUE, description, department, team_lead_id, is_active)` | `department` is a free-text label, currently partial. |
| Team default permissions | `team_privileges (team_id UNIQUE, can_manage_* , can_view_finance)` | **UI-only gate.** Not consulted by table RLS (except the app uses `can_view_finance` to route the Finance screen). |
| Per-user permission override | `user_privileges (user_id UNIQUE, can_manage_*, can_view_finance)` | Same: UI-only; RLS does not read it. |
| Client identity | `client_profiles.id` = `profiles.id` = `auth.users.id` (FK chain) | This is why `client_id = auth.uid()` works in client RLS. |

**Effective-permission resolution (app side)** — [team_privileges_notifier.dart](lib/core/providers/team_privileges_notifier.dart): `user_privileges` override → `team_privileges` (managers w/ team) → manager default (`true` for most, `false` for finance) → `false`. Admins bypass in callers (`isAdmin || canX`). **These flags gate the UI only; the database does not enforce them** (confirmed: manager RLS policies check team membership, never the flags).

**Team resolution (app side)** — [profile_repository.dart](lib/core/repositories/profile_repository.dart) loads the profile with `.eq('id', id).single()` (relies on the `Users read own profile` policy). The team is simply `profile.teamId`. User creation / role changes go through the **service-role admin client** (`SupabaseService.adminClient`), which **bypasses RLS** entirely.

**Super-admin derivation (app side)** — [profile_model.dart:45](lib/core/models/profile_model.dart#L45): `isSuperAdmin => role == 'super_admin'`. Because the enum has no such value, **`isSuperAdmin` is always false today** and `isAdmin` collapses to `role == 'admin'`. The entire Super-Admin tier is currently inert at the data layer.

---

## 3. Schema inventory (relevant subset)

### 3.1 Core scoping columns
- `tasks (team_id → teams, client_id → client_profiles, created_by → profiles, parent_task_id → tasks, board_id, board_column_id, handoff_from_team_id → teams, handoff_to_team_id → teams, hidden_from_client)` — **team-scoped + client-scoped + cross-team handoff.**
- `profiles (team_id → teams, role, status)`.
- `crm_entries / crm_payments (client_id → client_profiles)` — **client-scoped, no team column.**
- `expenses (category_id, recorded_by, approved_by)` — **no team/department column (company-wide).**
- `events (client_id → client_profiles, created_by → profiles, is_client_visible)` — **no team column**; department scope is only inferable via `created_by`'s team or `client_id`.
- `penalties (employee_id → profiles, penalty_type_id, approved_by)`, `attendance (employee_id → profiles)` — person-scoped.

### 3.2 Enums (department-relevant)
- `user_role`: `admin, employee, client, manager` — **no `super_admin`**.
- `task_status`: `not_started, in_progress, employee_done, client_approved, client_rejected, completed, on_hold, Client_Remake`.
- `notification_type`: includes `task_handoff, handoff_accepted, handoff_rejected, team_changed, role_changed` (supports cross-department handoff flows).

### 3.3 Integrity constraints (selected, confirmed)
- `profiles_id_fkey`: `profiles.id → auth.users(id) ON DELETE CASCADE`.
- `profiles_team_id_fkey`: `→ teams(id) ON DELETE SET NULL`.
- `client_profiles_id_fkey`: `→ profiles(id) ON DELETE CASCADE`.
- `tasks_team_id_fkey` / `tasks_handoff_*_team_id_fkey`: `→ teams(id) ON DELETE SET NULL`.
- `team_privileges_team_id_fkey`: `→ teams(id) ON DELETE CASCADE`; `user_privileges_user_id_fkey`: `→ profiles(id) ON DELETE CASCADE`.
- Unique: `attendance (employee_id, attendance_date)`, `room_bookings (room_id, booking_date, start_time)`, `task_approvals (task_id)`, `task_assignees (task_id, profile_id)`, `team_privileges (team_id)`, `user_privileges (user_id)`, `teams (name)`, `client_task_visibility (team_id, client_id)`.

### 3.4 Triggers & functions (relevant)
- Role/team guard: trigger `guard_profile_privileged_fields` (SECURITY DEFINER) blocks a non-admin from changing **their own** `role`/`status`/`team_id`. **This will need to recognize `super_admin` if that role is added.**
- Scoping helpers (SECURITY DEFINER, `STABLE`): `get_my_role()`, `is_manager()`, `my_team_id()`, `manager_*_ids()`. **These compare only against `admin`/`manager`; a new `super_admin` would be excluded unless updated.**
- CRM automation: `create_crm_from_task`, `create_crm_from_booking`, `sync_crm_payment_status` (SECURITY DEFINER).
- Notification fan-out: `notify_fanout`, `notify_*`, `tg_notifications_fcm_push` (SECURITY DEFINER).

---

## 4. RLS audit (core tables) — exact rules & risk

All 50 tables have RLS enabled. Pattern: one `admin` ALL policy (`get_my_role() = 'admin'`), one `manager` ALL policy (team-scoped via helpers), and narrow self/role SELECT/UPDATE policies.

### 4.1 Confirmed access rules (summarized from actual `qual`/`with_check`)
| Table | Admin | Manager | Employee | Client |
|---|---|---|---|---|
| `profiles` | ALL | SELECT self+team+their clients; UPDATE team members (not self, not →admin) | read/update **own** (guard trigger blocks role/status/team self-change) | read own only |
| `teams` | ALL | **ALL on own team row** (`id = my_team_id()`) | SELECT all | none |
| `tasks` | ALL | ALL where `team_id = my_team_id()`; SELECT where `handoff_to_team_id = my_team_id()` | SELECT/UPDATE/DELETE where `created_by = uid` OR assignee; INSERT where `created_by = uid` | none on base table (uses client view) |
| `task_assignees`/`task_comments`/`task_approvals` | ALL | ALL where task ∈ `manager_task_ids()` | own assignment/comment; employee/client update of their approval fields | client reads non-internal comments & own approvals |
| `events` | ALL | ALL where client ∈ team clients OR `created_by` ∈ team members | SELECT own/attendee | SELECT own `client_id` where `is_client_visible` |
| `event_attendees` | ALL | ALL where event ∈ `manager_event_ids()` | read own row | read own row |
| `attendance` | ALL | ALL where employee ∈ team members | ALL where `employee_id = uid` | none |
| `crm_entries`/`crm_payments` | ALL | ALL where client ∈ `manager_client_ids()` | none | SELECT where `client_id = uid` |
| `expenses` | **ALL (only policy)** | **none** | none | none |
| `penalties` | ALL | ALL where employee ∈ team members | **none** | none |
| `notifications` | INSERT (admin/service); read/update own | read/update own | read/update own | read/update own |
| `team_privileges` | ALL | SELECT own team | none | none |
| `user_privileges` | ALL | ALL for own-team members | SELECT own | none |

### 4.2 Confirmed finding — `super_admin` is locked out of every admin policy
Every "admin" policy compares `get_my_role() = 'admin'` (or a sub-select to `role = 'admin'`). If `super_admin` is introduced as a role **without updating these policies**, super-admins would **lose** admin access rather than gain global access. **Evidence:** policy `qual` strings above. **Required change** for the redesign.

### 4.3 Confirmed finding — privilege flags are not DB-enforced
`team_privileges.can_manage_expenses = true` grants nothing: `expenses` has no manager policy. Likewise `can_manage_penalties`/`can_manage_attendance` are honored only by the UI; the DB relies on team membership. **Implication for redesign:** department boundaries must be enforced through the `manager_*_ids()` / `my_team_id()` helpers (as today), not the flags. This is more-restrictive-than-advertised, not a leak.

### 4.4 Confirmed finding — SECURITY DEFINER views bypass RLS (cross-department/client exposure)
All 5 views are owned by `postgres`, have `security_invoker` unset (definer semantics → run as owner, bypassing the caller's RLS), and **`authenticated` AND `anon` both have SELECT** (verified with `has_table_privilege`).

| View | Internal row filter | Verdict |
|---|---|---|
| `tasks_client_view` | `WHERE client_id IN (SELECT id FROM client_profiles WHERE id = auth.uid())` | **Safe** (self-filtering) |
| `crm_client_view` | `WHERE client_id IN (… id = auth.uid())` | **Safe** (self-filtering) |
| `tasks_employee_view` | **none** (`SELECT … FROM tasks`) | **EXPOSED — every task, all teams/clients** |
| `admin_tables_overview` | **none** (all `custom_tables` joined) | **EXPOSED — all custom-table metadata** |
| `client_task_config_view` | **none** (all `client_task_visibility`) | **EXPOSED — all team↔client visibility configs** |

**Failure scenario (confirmed by construction):** a holder of the project's public anon key issues `GET /rest/v1/tasks_employee_view` and receives all 256 tasks regardless of team/client — the department boundary and client isolation enforced on the base `tasks` table do not apply. **The 3 exposed views are not referenced anywhere in the Flutter code** (grep returned no hits), so they appear to be dead objects. Remediation (implementation phase, with approval): set `security_invoker = on`, or add an `auth.uid()` filter, or drop them. *Not acting now per read-only scope.*

### 4.5 Lower-severity observations (not labeled vulnerable without more evidence)
- **`teams` manager policy is `ALL`** (`manager_team_teams`): at the DB level a manager can `UPDATE`/`DELETE` *their own* team row (`id = my_team_id()`), including `department`, and a delete would `SET NULL` dependent `tasks.team_id`/`profiles.team_id` and `CASCADE` `team_privileges`/`task_boards`. The Flutter router blocks managers from `/teams`, so this is reachable only via direct API calls. **Recommend** narrowing to `SELECT`/`UPDATE` (not `DELETE`) during the redesign. *Needs product confirmation that manager self-edit of the team is intended.*
- **Cross-department client bleed:** `manager_client_ids()` includes any client with a task in the manager's team. One client currently spans two teams, so that client's finance (`crm_entries`/`crm_payments`) and events are visible to managers of **both** departments. By design today; see §7.4.
- **`penalties` has no employee self-read policy**, yet the app exposes a "my penalties" screen to employees and the router allows `/penalties` for employees. At the DB level an employee query returns **zero rows**. **UNVERIFIED** whether the feature is broken or served another way — worth a functional check, independent of the redesign.

---

## 5. Foreign keys & data integrity

- **FKs exist and are enforced** (108 total; see §0 and §3.3). Orphaned rows are **structurally impossible** for any FK column — the constraint rejects them. No orphan scan is needed for FK-backed relationships, and none was possible to find.
- **Non-FK (polymorphic) links** are the only place dangling references can occur: `notifications (reference_type, reference_id)`, `note_links (link_type, linked_id)`. **Confirmed:** **353** `notifications` rows have `reference_type = 'task'` pointing at a `reference_id` with no matching `tasks` row. This is expected for an append-only notification log after task deletion/archival; it is **not** corruption of an enforced relationship and requires **no cleanup**. (Distinguish: *confirmed integrity problem* = none; *potential risk* = polymorphic deep-links can 404 in the UI.)
- Supporting indexes for relationships exist on all hot scoping columns: `idx_tasks_team`, `idx_tasks_client`, `idx_profiles_team_id`, `idx_crm_client`, `idx_pay_client`, `idx_att_employee`, `idx_pen_employee`, `idx_notif_recip`, `idx_tboards_team`, `idx_ctv_team/client`, etc.

---

## 6. Flutter code map (modules responsible for these concerns)

| Concern | Source paths |
|---|---|
| Auth / session / role state | [core/auth/auth_notifier.dart](lib/core/auth/auth_notifier.dart) |
| Role constants (incl. aspirational `super_admin`) | [core/constants/app_roles.dart](lib/core/constants/app_roles.dart) |
| Profile model + `isSuperAdmin/isAdmin/isManager` | [core/models/profile_model.dart](lib/core/models/profile_model.dart) |
| Team resolution / user mgmt (service-role writes) | [core/repositories/profile_repository.dart](lib/core/repositories/profile_repository.dart) |
| Effective permissions (UI gate) | [core/providers/team_privileges_notifier.dart](lib/core/providers/team_privileges_notifier.dart), `team_privileges_repository.dart`, `user_privileges_repository.dart` |
| Route/role guard | [core/router/app_router.dart](lib/core/router/app_router.dart) |
| Teams / members / privileges UI | `features/teams/*`, `features/roles/roles_editor_screen.dart`, `features/users/*` |
| Tasks / finance / attendance / penalties / expenses | `features/tasks/*`, `features/finance/*`, `features/attendance/*`, `features/penalties/*`, `features/expenses/*` |
| Super-admin-only tools (app-gated) | `features/super_admin/*`, `core/repositories/reset_app_repository.dart`, `core/utils/super_admin_pdf_exporter.dart` |

**How the app resolves a user's team + permissions today:** login → `auth_notifier` fetches `profiles` row (RLS `read own`) → `profile.teamId` is the department; `profile.role` is the tier → `team_privileges_notifier` loads `team_privileges(team_id)` and `user_privileges(user_id)` for UI gating → `app_router` redirect guard restricts routes by role. DB RLS independently enforces team-scoping for managers and self-scoping for employees/clients.

---

## 7. Recommended smallest-safe department architecture

### 7.1 Reuse `teams` as departments — **no separate `departments` entity required**
**Rationale (evidence-based):** `teams.department` already exists; one team per department already; all tasks already carry `team_id`; RLS, helpers, indexes, and the app are all built around `team_id`. Introducing a parallel `departments` table + re-pointing 108 FKs/RLS would be a large, risky change for no functional gain at the current 1:1 scale.

**Only** introduce a normalized `departments` lookup (+ `teams.department_id` FK) **if** the product needs multiple teams inside one department. At 5 departments ≈ 5 teams, that is not yet justified. (ASSUMPTION A1.)

### 7.2 Membership model
- Keep `profiles.team_id` as the single source of department membership for managers/employees.
- Global tiers (Admin, Super Admin) = `team_id` irrelevant; access is role-based.
- If multi-department staff ever appear (A4 says no), add a junction `profile_teams(profile_id, team_id, is_primary)` later — not now.

### 7.3 Role tiers (requires the one unavoidable change)
Two reversibility options — **pick one before implementation:**

| Option | Change | Reversible? | App impact |
|---|---|---|---|
| **B1 (matches app)** | `ALTER TYPE user_role ADD VALUE 'super_admin'` | **No** (enum values can't be dropped cleanly; also can't run inside a txn) | App already expects it; minimal code change |
| **B2 (reversible)** | Add `profiles.is_super_admin boolean NOT NULL DEFAULT false` | **Yes** | App must switch `isSuperAdmin` to read the flag |

Either way, **update every admin RLS check and the helpers/guard** to treat super-admin as global, e.g. a new `is_global_admin()` SECURITY DEFINER helper = `get_my_role() = 'admin' OR <super-admin test>`, and replace `get_my_role() = 'admin'` in admin policies with it. Without this, §4.2 locks super-admins out.

### 7.4 Behavior of each domain
- **Expenses:** **unchanged** — company-wide, admin-only. No team/department column. (Meets requirement directly.)
- **Department finance (`crm_*`):** keep client-based scoping. Decide the shared-client policy (A3): (a) accept that managers of every team serving a client see that client's finance, or (b) add a nullable `crm_entries.team_id` (+ backfill from the source task's team) to pin each invoice to the originating department and tighten the manager policy to `team_id = my_team_id()`. Option (a) = zero schema change; option (b) = smallest change that removes cross-department finance bleed.
- **Existing clients:** unchanged. Client self-access (`client_id = auth.uid()`) and `client_task_visibility` per (team, client) continue to work.
- **Existing tasks:** unchanged — already 100% `team_id`-tagged, so already department-scoped. Cross-department handoff already modeled (`handoff_to_team_id`).
- **Calendar/events:** events have **no `team_id`**. If department-scoped calendars are required, either (i) derive department from `created_by`'s team (current implicit behavior) or (ii) add nullable `events.team_id`. Smallest safe = keep implicit; add the column only if explicit department calendars are a requirement.

### 7.5 Required RLS changes (minimal set)
1. Add super-admin recognition to: all `*_admin*` policies, `guard_profile_privileged_fields`, and optionally the `manager_*` helpers (super-admin shouldn't be team-limited). (Required.)
2. Backfill `teams.department` for `Admins` and `Sales`; create `Production`/`Studio` teams (or rename `Video Production`→`Production`) per A1. (Data-only.)
3. Remediate the 3 unfiltered SECURITY DEFINER views (§4.4): `security_invoker = on`, or add `auth.uid()` filters, or drop (they're unused). (Strongly recommended, independent of departments.)
4. (Optional, finance precision) `crm_entries.team_id` + tightened manager policy (§7.4b).
5. (Optional, hardening) narrow `manager_team_teams` from `ALL` to `SELECT`/`UPDATE`.

---

## 8. Proposed migration sequence (for the implementation phase — not executed)

> All steps are forward-only migrations to run with explicit approval. Each is wrapped in a transaction **except** B1's `ADD VALUE` (cannot run in a txn block).

1. **Data backfill** `teams.department` for all teams; create any missing department teams. *(reversible)*
2. **Super-admin tier** — Option B2 (recommended for reversibility): add `profiles.is_super_admin` + promote the designated owner(s). *(reversible)* — or B1 enum add. *(irreversible)*
3. **RLS/helpers** — add `is_global_admin()`; swap admin-policy predicates; update the guard trigger. *(reversible)*
4. **View remediation** — `ALTER VIEW … SET (security_invoker = on)` on the 3 exposed views (or drop). *(reversible)*
5. **(Optional) finance precision** — add `crm_entries.team_id`, backfill from `tasks.team_id` via `source_id`, tighten policy. *(reversible)*
6. **App changes** — if B2: point `ProfileModel.isSuperAdmin` at the flag; otherwise no code change. Verify router/privilege gates.
7. **Regression pass** — run the §10 test matrix against a staging project before production.

---

## 9. Backward compatibility & rollback

- **Steps 1, 3, 4, 5, 6 are reversible** (restore prior policy/trigger definitions, drop the added column, restore view options).
- **Step 2/B1 (`enum ADD VALUE`) is effectively irreversible** — prefer **B2 (boolean flag)** unless the team specifically wants the enum to match existing app strings.
- **No destructive data operations are proposed.** Existing rows keep their `team_id`/`role`; no deletes, no FK drops, no cleanup of the 353 dangling notification references.
- **Compatibility:** because managers are already single-team and tasks are already team-tagged, existing users retain identical access after Steps 1–4. The only behavior change is: super-admins gain global access (previously inert), and the 3 dead views stop leaking.
- **Rollback trigger points:** after Step 3, verify admin + super-admin can still read every module; if not, re-apply the previous policy snapshot (capture `pg_policies` + `pg_get_functiondef` outputs *before* changing anything).

---

## 10. Test matrix (role × module × boundary)

Legend: ✅ allowed · ⛔ denied · 🔒 own-scope only.

| Scenario | Super Admin | Admin | Manager (Dept A) | Employee (Dept A) | Client |
|---|---|---|---|---|---|
| Read tasks in **own** dept | ✅ | ✅ | ✅ | 🔒 (assigned/created) | 🔒 (own via client view) |
| Read tasks in **other** dept | ✅ | ✅ | ⛔ | ⛔ | ⛔ |
| Write task in other dept | ✅ | ✅ | ⛔ | ⛔ | ⛔ |
| Accept cross-dept **handoff** to own team | ✅ | ✅ | ✅ (`handoff_to_team_id`) | n/a | n/a |
| Read team members (own dept) | ✅ | ✅ | ✅ | profiles: self only | ⛔ |
| Read members of other dept | ✅ | ✅ | ⛔ | ⛔ | ⛔ |
| Finance (`crm_*`) own-dept client | ✅ | ✅ | ✅ | ⛔ | 🔒 own only |
| Finance for **shared** client (A3) | ✅ | ✅ | ✅ (both depts today) | ⛔ | 🔒 own |
| Expenses (company-wide) | ✅ | ✅ | ⛔ (confirmed) | ⛔ | ⛔ |
| Penalties own-dept employee | ✅ | ✅ | ✅ | **⛔ (no self-read policy — verify)** | ⛔ |
| Attendance own record | ✅ | ✅ | ✅ (team) | 🔒 own | ⛔ |
| Calendar event other dept | ✅ | ✅ | ⛔ unless creator/client in team | 🔒 own/attendee | 🔒 own visible |
| Change **own** role/team | ⛔ (guard) | ✅ | ⛔ (guard) | ⛔ (guard) | ⛔ |
| `GET tasks_employee_view` (anon key) | — | — | — | — | **must become ⛔ after §4.4 fix (today: ✅ all tasks)** |
| Super-admin global access after migration | ✅ (must verify Step 3) | ✅ | 🔒 dept | 🔒 | 🔒 |

**Boundary cases to script explicitly:** (1) manager of Dept A querying Dept B rows on every table; (2) the one shared client across two departments; (3) employee reading own penalties; (4) all 5 views with the anon key pre/post fix; (5) super-admin on every admin-only table after the RLS change; (6) a team delete via API as a manager (should be blocked after §7.5.5).

---

## 11. Open questions / unverified items
- **A1:** Is `Video Production` the `Production` department (rename) or separate? Is `Studio` a new team to create? Do `Admins`/`Sales` need `department` labels?
- **A2:** Any DB-level (not just app-level) capability that Super Admin has but Admin does not?
- **A3:** Desired policy for clients served by multiple departments (accept shared visibility vs. pin invoices to a department).
- **Penalties employee self-read** (§4.5): is the "my penalties" employee screen expected to work? It currently returns no rows at the DB level — **unverified** whether this is a bug or intentional.
- Whether the 3 unused views may be dropped vs. must be preserved for some external consumer (no in-repo usage found; external consumers unverified).

---

*End of assessment. No changes were made to the database, its policies/functions/triggers/data, or application files. Awaiting approval before any implementation.*
