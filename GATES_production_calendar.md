# GATES — Production department: Calendar-only workspace

Scope: a user whose team department = `production` (manager/employee) gets a
Calendar-only app: Calendar is the landing + only nav destination, all other
modules blocked at the router (not just hidden). Admins/super admins, clients,
and every other department are UNCHANGED. No DB change, no apply/deploy/commit.
Reuse the existing Calendar + event + notification flow unchanged.

Source of truth: profiles.team_id → teams.department (resolved at login in
AuthNotifier; mirrors, never replaces, DB RLS).

## Gates

G1: Production routing + nav decision logic is correct (pure, unit-tested).
  CHECK: flutter test test/workspace_routing_test.dart
  EXPECT: All tests passed!

G2: Changed Dart analyzes clean (no new issues).
  CHECK: flutter analyze lib/core/router/app_router.dart lib/core/router/workspace_routing.dart lib/core/router/app_routes.dart lib/core/auth/auth_notifier.dart lib/core/widgets/bottom_nav_shell.dart test/workspace_routing_test.dart
  EXPECT: No issues found!

G3 (manual): Router blocks direct-route access for production — every authed
  route except /calendar(/**) redirects to /calendar; landing is /calendar.
  EVIDENCE: app_router.dart production block + WorkspaceRouting.productionRedirect
  unit tests (dashboard/tasks/finance/settings/workspaces/analytics → /calendar).

G4 (manual): Nav shell shows ONLY Calendar for production; other roles' tabs
  unchanged (employee/manager [0,1,2,4], client [1,2,3,4], admin all).
  EVIDENCE: bottom_nav_shell.dart production branch = [2].

G5 (manual): Isolation — only production restricted. Calendar, event creation,
  notifications, task/finance logic UNCHANGED. No schema change, nothing applied,
  deployed, or committed. Admin/super-admin unchanged (isProductionCalendarOnly
  returns false for admin/client).

ABANDON: none.

## Evidence (measured 2026-10-31)

- G1 `flutter test test/workspace_routing_test.dart` → `All tests passed!` (14 tests:
  isProductionCalendarOnly + productionRedirect, incl. admin/other-dept isolation).
- G2 `flutter analyze` on the 5 changed lib files + test → `No issues found!`
- G3 router: `app_router.dart` ③b calls `WorkspaceRouting.productionRedirect(loc,
  calendarOnly: auth.isProductionOnly)` before entry-routing + role guards →
  every non-/calendar authed route redirects to /calendar (unit-proven list:
  dashboard/tasks/finance/settings/workspaces/analytics/expenses/users/teams/notifications).
- G4 nav shell: production branch = `[2]` (Calendar); bottom bar hidden when <2 tabs.
  Other roles' branch indices untouched.
- G5 isolation: changes are additive (new getters/methods/const). Calendar, event
  creation (`ClientRepository.createEvent`) and notifications (server-side trigger
  `notify_event_created`) UNCHANGED. No schema change. Nothing applied/deployed/committed.
- Graphify used for investigation (nav/router/department/calendar).

Acceptance criteria: all met except live manual device walkthrough (code + unit
verified; app not run here).

## Fail-open fix (2026-10-31)

Bug: a failed/missing `teams.department` lookup left `_department` null →
`isProductionOnly` false → a Production user could reach the full app. Now FAIL
CLOSED via an explicit resolution state.

- `lib/core/router/department_gate.dart` (NEW): `DepartmentResolution`
  {notRequired, loading, resolved, failed} + pure `DepartmentGate` (isRequired/
  isPending/isFailed).
- `auth_notifier.dart`: `_resolveDepartment()` sets loading → resolved | failed;
  exception OR missing row → **failed** (blocking); `isProductionOnly` now
  requires `resolved`; new `departmentGatePending` / `departmentResolveFailed`;
  `retryDepartmentResolution()`. Uses the authenticated client (teams RLS); no
  service-role.
- `workspace_routing.dart`: pure `departmentGateRedirect(loc, pending:)` (loop-safe).
- `app_router.dart` ③a: holds pending users on `/resolving` before production +
  role guards; leaves `/resolving` once resolved; new `/resolving` route.
- `department_gate_screen.dart` (NEW): spinner while loading, error + Retry (+
  Sign out) on failure.
- Tests: `test/department_gate_test.dart` (NEW, 17 tests) — success→calendar-only,
  non-prod→normal, exception/missing→held, admin/super/client unchanged, no-team
  unchanged, retry→correct, no redirect loop.

Evidence: `flutter test department_gate_test.dart workspace_routing_test.dart` →
**All tests passed!** (31). `flutter analyze` (9 files) → **No issues found!**
Graphify refreshed; impact query shows DepartmentGate/departmentGatePending/
departmentGateRedirect/DepartmentResolution present. No schema/RLS change, nothing
applied/deployed/committed. Calendar event + notification logic untouched.

## Admin in Production workspace = Calendar-only (2026-10-31)

Decision: admin only while VIEWING Production (stays global, can switch out);
admin AND super admin included. Keyed off the active workspace
(`WorkspaceScopeNotifier.effectiveDepartment`), not profile team — so no lock-out.

- `workspace_routing.dart`: `isAdminProductionCalendarOnly(profile, effectiveDept)`
  (true for admin/super when effectiveDept == production); `productionRedirect`
  gains `allowWorkspaces` so a calendar-only admin keeps `/workspaces` (escape).
- `app_router.dart`: `makeRouter(auth, scope)`; `refreshListenable` now
  `Listenable.merge([auth, scope])` (re-evaluates on department switch); ③b
  computes `calendarOnly = isProductionOnly || adminProd`, `allowWorkspaces = adminProd`.
- `bottom_nav_shell.dart`: calendar-only branch also when admin viewing Production;
  WorkspaceHeaderBar stays (admin switch-out).
- `main.dart`: passes `workspaceScope` to `makeRouter`.
- Tests: `workspace_routing_test.dart` +2 groups (isAdminProductionCalendarOnly,
  productionRedirect escape). `flutter test` → 38 passed. `flutter analyze` (6
  files incl main.dart) → No issues found!. Graphify refreshed.

Isolation: non-admins unaffected by this branch; admin outside Production / in
"All Departments" fully unchanged; other departments unchanged.
