-- ============================================================================
-- PROPOSED (NOT APPLIED) — needs explicit approval. Three unrelated DB items
-- grouped for review. Nothing here has run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) Super-Admin DB gate for global/destructive ops (Step 6).
--    Today reset_app / archiveCompletedTasks run via the service-role client
--    from a super-admin-only screen → NOT gated at the DB. Move them behind
--    SECURITY DEFINER RPCs that verify is_super_admin from auth.uid().
--    After apply, wire repo: _client.rpc('archive_completed_tasks').
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_completed_tasks()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_actor uuid := auth.uid(); v_count int;
BEGIN
  IF v_actor IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_actor AND is_super_admin) THEN
    RAISE EXCEPTION 'Super admin only.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  WITH upd AS (
    UPDATE public.tasks
      SET is_archived = true, archived_at = now(), archived_by = v_actor, updated_at = now()
    WHERE status = 'completed' AND (is_archived IS NULL OR is_archived = false)
    RETURNING 1
  ) SELECT count(*) INTO v_count FROM upd;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.archive_completed_tasks() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.archive_completed_tasks() TO authenticated;

-- reset_app is large (multi-table delete). Same pattern, but prepare carefully:
-- a guarded RPC `reset_app()` that first runs this assertion, then performs the
-- existing deletes server-side. Outline only — full body to be written against
-- reset_app_repository's exact table list, then reviewed before apply.
CREATE OR REPLACE FUNCTION public.assert_super_admin()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_admin) THEN
    RAISE EXCEPTION 'Super admin only.' USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- B) get_profile_by_email least-privilege (Step 5/7).
--    Now RETURNS SETOF profiles (every column incl. fcm_token, telegram_chat_id,
--    phone, avatar). Only caller is team_members_screen, which uses id, role,
--    status, full_name, team_id. Narrow to those. Return-type change needs DROP.
--    App compatibility: ProfileModel.fromMap defaults the omitted columns, so
--    the single caller keeps working.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_profile_by_email(text);
CREATE FUNCTION public.get_profile_by_email(user_email text)
RETURNS TABLE(id uuid, role public.user_role, status public.user_status,
              full_name text, team_id uuid)
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p.id, p.role, p.status, p.full_name, p.team_id
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE lower(u.email) = lower(user_email)
    AND auth.uid() IS NOT NULL
  LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION public.get_profile_by_email(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_profile_by_email(text) TO authenticated;

-- ----------------------------------------------------------------------------
-- C) Expenses write authorization — DECISION NEEDED, no SQL chosen yet (Step 4).
--    Conflict: `expenses` RLS is admin-only, but expense_repository
--    (createExpense/approveExpense/rejectExpense) runs via service-role and the
--    code/docs say "Admin / manager". So managers can write expenses today ONLY
--    by bypassing RLS.
--    The rule "managers must not gain COMPANY-WIDE expense access" is about
--    reads/scope, not necessarily writes. Two clean options — pick one:
--      Option 1 (expenses are admin-only): convert expense writes to _client.
--        Managers lose expense create/approve. No new policy. Smallest.
--      Option 2 (managers manage their team's expenses): add a team-scoped
--        write policy (NOT company-wide), e.g.:
--        -- CREATE POLICY "manager_team_expense_write" ON public.expenses FOR ALL
--        --   USING (is_manager() AND recorded_by IN (SELECT id FROM manager_member_ids()))
--        --   WITH CHECK (is_manager() AND recorded_by IN (SELECT id FROM manager_member_ids()));
--        then convert expense writes to _client. Managers still cannot see/write
--        company-wide expenses — only their team's recorders.
--    No expense code was changed; tell me Option 1 or 2.
