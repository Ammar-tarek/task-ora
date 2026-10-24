-- ============================================================================
-- PROPOSED (NOT APPLIED) — needs explicit approval.
-- Unblocks moving penalty reads to the RLS client (B2 remainder).
--
-- Problem: public.penalties has admin + manager-team SELECT policies but NO
-- employee-self policy. Employees currently see their own penalties ONLY because
-- penalty_repository reads via the service-role client (bypassing RLS). To move
-- those reads onto the authenticated RLS client without removing that legitimate
-- access, add an employee-self SELECT policy first.
--
-- Impact: employees can read ONLY their own penalty rows; no change for admin/
-- manager; no new cross-employee or cross-department visibility.
-- Rollback: DROP POLICY "Employee reads own penalties" ON public.penalties;
-- ============================================================================
CREATE POLICY "Employee reads own penalties"
  ON public.penalties
  FOR SELECT
  USING (employee_id = auth.uid());

-- After this is applied and verified, convert penalty_repository reads
-- (fetchAll, fetchForEmployee, fetchEmployees, the assignable-profiles lookup)
-- from SupabaseService.adminClient to SupabaseService.client, mirroring the
-- attendance/finance/expense B2 changes. Then re-run REGRESSION_isolation_checks.sql
-- and confirm: employee penalties = own only; manager = team; admin = all.
