-- ============================================================================
-- REGRESSION — Department isolation, proven under REAL authenticated sessions.
-- READ-ONLY / non-mutating: each block sets the authenticated role + a user's
-- JWT claim (so auth.uid() = that user and RLS applies — NOT service-role), then
-- asserts what that user can see/do. Write checks use ROLLBACK and no-op values.
--
-- This is the correct way to prove RLS without the Flutter app: `set local role
-- authenticated` + `request.jwt.claims.sub` makes every policy + helper
-- (is_global_admin/my_team_id/get_my_role) resolve for that user.
--
-- Subjects (prod, 2026-10-24):
--   Marketing emp  Lina         cf85b8f4-34f7-4b11-b344-9069ee74cd94
--   Marketing mgr  Youssef      42eed13e-2f84-4c40-860c-9348aa1f1ea1
--   Montage  mgr   Mena         8f9cf5b0-0184-4eeb-8232-e7f939e173aa
--   Admin          MOMO         1cd0976f-8363-4be2-af62-d0205d43c29c
--   Client         saif         e3607042-9221-41d1-8d1c-56cd91119ed2
--   Teams: Marketing f398bbb2… · Montage c87fe040…
--   Sample tasks: mkt ed7a0bee… · montage 3d1b4e0e…
-- Run each block on its own. Expected results are in comments. ✅ = verified pass.
-- ============================================================================

-- 1) Marketing EMPLOYEE sees only own work; nothing cross-dept. ✅
-- expect: montage_tasks 0, mon_task_by_id 0, others_att 0, others_notifs 0,
--         others_penalties 0, company_ledger 0.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cf85b8f4-34f7-4b11-b344-9069ee74cd94","role":"authenticated"}';
  select
    (select count(*) from tasks where team_id='c87fe040-382d-43fd-9a80-3ddc798782b6') as montage_tasks,
    (select count(*) from tasks where id='3d1b4e0e-4fa8-4e87-90ce-88527e8d9125')      as mon_task_by_id,
    (select count(*) from attendance where employee_id <> auth.uid())                 as others_att,
    (select count(*) from notifications where recipient_id <> auth.uid())             as others_notifs,
    (select count(*) from penalties where employee_id <> auth.uid())                  as others_penalties,
    (select count(*) from company_ledger)                                             as company_ledger;
rollback;

-- 2) Montage MANAGER: no Marketing rows; no company finance. ✅
-- expect: marketing_tasks 0, mkt_task_by_id 0, mkt_emp_att 0, mkt_emp_penalty 0,
--         non_montage_leak 0, company_ledger 0, expenses 0.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"8f9cf5b0-0184-4eeb-8232-e7f939e173aa","role":"authenticated"}';
  select
    (select count(*) from tasks where team_id='f398bbb2-f5c2-4a1c-852e-745c911c1264') as marketing_tasks,
    (select count(*) from tasks where id='ed7a0bee-e124-4ad8-9369-ca9277137e14')       as mkt_task_by_id,
    (select count(*) from tasks where team_id is distinct from 'c87fe040-382d-43fd-9a80-3ddc798782b6'
        and handoff_to_team_id is distinct from 'c87fe040-382d-43fd-9a80-3ddc798782b6') as non_montage_leak,
    (select count(*) from attendance where employee_id='cf85b8f4-34f7-4b11-b344-9069ee74cd94') as mkt_emp_att,
    (select count(*) from penalties  where employee_id='cf85b8f4-34f7-4b11-b344-9069ee74cd94') as mkt_emp_penalty,
    (select count(*) from company_ledger) as company_ledger,
    (select count(*) from expenses)       as expenses;
rollback;

-- 3) CLIENT: no internal data at all. ✅
-- expect: others_client_tasks 0, mkt_task_by_id 0, attendance 0, others_crm 0,
--         company_ledger 0, penalties 0.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"e3607042-9221-41d1-8d1c-56cd91119ed2","role":"authenticated"}';
  select
    (select count(*) from tasks where client_id is distinct from auth.uid())        as others_client_tasks,
    (select count(*) from tasks where id='ed7a0bee-e124-4ad8-9369-ca9277137e14')    as mkt_task_by_id,
    (select count(*) from attendance)                                               as attendance,
    (select count(*) from crm_entries where client_id is distinct from auth.uid())  as others_crm,
    (select count(*) from company_ledger)                                           as company_ledger,
    (select count(*) from penalties)                                                as penalties;
rollback;

-- 4) ADMIN: global (company-wide), by design. ✅
-- expect: is_admin t, tasks=all, attendance=all, penalties=all, ledger=all.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"1cd0976f-8363-4be2-af62-d0205d43c29c","role":"authenticated"}';
  select public.is_global_admin() as is_admin,
    (select count(*) from tasks) as tasks, (select count(*) from attendance) as attendance,
    (select count(*) from penalties) as penalties, (select count(*) from company_ledger) as ledger;
rollback;

-- 5) WRITE DENY — Montage mgr cannot update a Marketing task. ✅ (expect 0 rows)
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"8f9cf5b0-0184-4eeb-8232-e7f939e173aa","role":"authenticated"}';
  with upd as (update public.tasks set status=status
    where id='ed7a0bee-e124-4ad8-9369-ca9277137e14' returning 1)
  select count(*) as cross_team_rows_updated from upd;  -- expect 0
rollback;

-- 6) GUARD — employee cannot edit management fields (expect ERROR 42501). ✅
-- begin; set local role authenticated; set local request.jwt.claims '…Lina…';
--   update tasks set cost = coalesce(cost,0)+1 where id in
--     (select task_id from task_assignees where profile_id=auth.uid());  -- RAISES
-- rollback;

-- 7) GUARD — employee cannot self-complete (expect ERROR 42501). ✅
-- begin; …Lina…; update tasks set status='completed' where id in
--   (select task_id from task_assignees where profile_id=auth.uid());    -- RAISES
-- rollback;

-- 8) RPC AUTH — non-admin add_funds / foreign assignment reject (expect ERRORs). ✅
-- …Lina…; select company_add_funds(100,current_date,'x',gen_random_uuid()); -- RAISES admin-only
-- …Lina…; select respond_to_assignment('<montage task>','rejected','x');     -- RAISES not assigned
