-- ============================================================================
-- (NOT APPLIED) — Make "Assigned By" show for employees.
--
-- assigned_by is set on every task_assignees row, but an employee can only read
-- their OWN profile (profiles RLS), so the assigner's name (an admin/manager)
-- came back empty. This adds a narrow SELECT policy: a user may read the profile
-- of anyone who ASSIGNED them a task. Only exposes those assigners' profiles.
-- Apply in the Supabase SQL Editor.
-- ============================================================================
CREATE POLICY profiles_read_my_assigners ON public.profiles
  FOR SELECT TO authenticated
  USING (
    id IN (SELECT assigned_by FROM public.task_assignees WHERE profile_id = auth.uid())
  );
