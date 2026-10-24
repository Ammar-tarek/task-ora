-- ============================================================================
-- Department-isolation regression checks (read-only; re-runnable).
-- Simulates each role's JWT and asserts RLS scope. Run each block; compare to
-- Expected. Results captured 2026-10-18 after the isolation migration + B2.
-- (As the postgres/owner role you BYPASS RLS, so each block SET ROLE authenticated
--  and sets request.jwt.claims.sub to a real profile id.)
-- ============================================================================

-- MANAGER (Marketing, team f398…): tasks/attendance scoped to own team; expenses 0.
-- Expected: mgr_tasks=own-team only, foreign=0; attendance=team only; expenses=0.
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',id,'role','authenticated')::text from public.profiles where role='manager' and team_id='f398bbb2-f5c2-4a1c-852e-745c911c1264' limit 1),true);
  SET LOCAL ROLE authenticated;
  SELECT 'manager' role,
    (select count(*) from tasks) tasks,
    (select count(*) from tasks t where coalesce(t.team_id::text,'')<>'f398bbb2-f5c2-4a1c-852e-745c911c1264' and coalesce(t.handoff_to_team_id::text,'')<>'f398bbb2-f5c2-4a1c-852e-745c911c1264') foreign_tasks,  -- Expected 0
    (select count(*) from attendance) attendance,
    (select count(*) from expenses) expenses,   -- Expected 0 (managers-no-expenses)
    (select count(*) from penalties) penalties;
ROLLBACK;
-- Result: tasks=41, foreign_tasks=0, attendance=316, expenses=0, penalties=0  ✓

-- MANAGER direct-ID access to ANOTHER team's task. Expected 0.
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',id,'role','authenticated')::text from public.profiles where role='manager' and team_id='f398bbb2-f5c2-4a1c-852e-745c911c1264' limit 1),true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) foreign_task_by_direct_id
  FROM tasks WHERE id=(select id from tasks where coalesce(team_id::text,'')<>'f398bbb2-f5c2-4a1c-852e-745c911c1264' and team_id is not null limit 1);
ROLLBACK;
-- Result: 0  ✓

-- EMPLOYEE: own tasks/attendance only; no expenses/penalties.
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',id,'role','authenticated')::text from public.profiles where role='employee' and team_id is not null limit 1),true);
  SET LOCAL ROLE authenticated;
  SELECT 'employee' role,
    (select count(*) from tasks) tasks,           -- Expected: only created/assigned
    (select count(*) from attendance) attendance, -- Expected: own only
    (select count(*) from expenses) expenses,     -- Expected 0
    (select count(*) from penalties) penalties;   -- Expected 0 (see note below)
ROLLBACK;
-- Result: tasks=1, attendance=21, expenses=0, penalties=0  ✓

-- ADMIN (non-super): company-wide.
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',id,'role','authenticated')::text from public.profiles where role='admin' and is_super_admin=false limit 1),true);
  SET LOCAL ROLE authenticated;
  SELECT 'admin' role, public.is_global_admin() is_global,
    (select count(*) from tasks) tasks, (select count(*) from attendance) attendance,
    (select count(*) from expenses) expenses, (select count(*) from penalties) penalties;
ROLLBACK;
-- Result: is_global=true, tasks=256, attendance=614, expenses=5, penalties=2  ✓

-- SUPER ADMIN (ammar): global reach, verified by DB flag (not the client hack).
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',p.id,'role','authenticated')::text from public.profiles p join auth.users u on u.id=p.id where lower(u.email)=lower('ammar@cashback.com')),true);
  SET LOCAL ROLE authenticated;
  SELECT 'super_admin' role, public.is_global_admin() is_global,
    (select count(*) from tasks) tasks, (select count(*) from attendance) attendance,
    (select count(*) from expenses) expenses;
ROLLBACK;
-- Result: is_global=true, tasks=256, attendance=614, expenses=5  ✓

-- CLIENT: no staff data; only own tasks/finance (via self-filtered views).
BEGIN;
  SELECT set_config('request.jwt.claims',(select json_build_object('sub',id,'role','authenticated')::text from public.profiles where role='client' limit 1),true);
  SET LOCAL ROLE authenticated;
  SELECT 'client' role,
    (select count(*) from tasks) base_tasks,      -- Expected 0 (uses tasks_client_view)
    (select count(*) from attendance) attendance, -- Expected 0
    (select count(*) from expenses) expenses,     -- Expected 0
    (select count(*) from penalties) penalties;   -- Expected 0
ROLLBACK;
-- Result: base_tasks=0, attendance=0, expenses=0, penalties=0  ✓

-- ANON via the previously-leaking SECURITY DEFINER views. Expected 0 after B1.
BEGIN;
  SET LOCAL ROLE anon;
  SELECT (select count(*) from tasks_employee_view) tasks_view,
         (select count(*) from admin_tables_overview) tables_view,
         (select count(*) from client_task_config_view) client_cfg_view;
ROLLBACK;
-- Result: 0, 0, 0  ✓

-- NOTE: employee penalties=0 is a PRE-EXISTING RLS gap (no employee-self SELECT
-- policy on penalties). Before B2, penalty_repository used the service-role
-- client so employees saw their own penalties. B2 did NOT convert penalty reads
-- for this reason — doing so would remove that access. See
-- PROPOSED_penalties_employee_read.sql for the policy that must land first.
