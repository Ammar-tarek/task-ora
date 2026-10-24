-- ============================================================================
-- PROPOSED (NOT APPLIED). Two SECURITY DEFINER RPCs that let the Flutter client
-- drop adminClient for notification fan-out and the handoff team picker, using
-- the authenticated session. Needs approval.
-- ============================================================================

-- notify_action: replaces NotificationRepository.notifyAction's service-role
-- fan-out. Any authenticated caller; recipients derived server-side (targets +
-- the team's lead/managers + all admins/super admins), actor excluded unless
-- explicitly targeted. Definer bypasses the admin-only INSERT policy safely.
CREATE OR REPLACE FUNCTION public.notify_action(
  p_title text,
  p_body text,
  p_type public.notification_type,
  p_reference_type text DEFAULT NULL,
  p_reference_id uuid DEFAULT NULL,
  p_team_id uuid DEFAULT NULL,
  p_target_user_ids uuid[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_actor uuid := auth.uid(); v_count int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  CREATE TEMP TABLE _r (id uuid PRIMARY KEY) ON COMMIT DROP;

  IF p_target_user_ids IS NOT NULL THEN
    INSERT INTO _r SELECT DISTINCT x FROM unnest(p_target_user_ids) x
    WHERE x IS NOT NULL ON CONFLICT DO NOTHING;
  END IF;

  IF p_team_id IS NOT NULL THEN
    INSERT INTO _r SELECT team_lead_id FROM public.teams
      WHERE id = p_team_id AND team_lead_id IS NOT NULL ON CONFLICT DO NOTHING;
    INSERT INTO _r SELECT id FROM public.profiles
      WHERE team_id = p_team_id AND role = 'manager' ON CONFLICT DO NOTHING;
  END IF;

  INSERT INTO _r SELECT id FROM public.profiles
    WHERE role = 'admin' OR is_super_admin = true ON CONFLICT DO NOTHING;

  -- Drop the actor unless explicitly targeted or a super admin.
  DELETE FROM _r WHERE id = v_actor
    AND NOT (p_target_user_ids IS NOT NULL AND v_actor = ANY (p_target_user_ids))
    AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_actor AND is_super_admin = true);

  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT id, p_type, p_title, p_body, p_reference_type, p_reference_id, false, 'in_app'
  FROM _r;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_action(text,text,public.notification_type,text,uuid,uuid,uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notify_action(text,text,public.notification_type,text,uuid,uuid,uuid[]) TO authenticated;

-- list_active_teams: replaces TeamRepository.fetchAllAdmin for the handoff
-- destination picker. Team id/name/department are not department-sensitive;
-- any authenticated staff may list active teams to pick a handoff target.
CREATE OR REPLACE FUNCTION public.list_active_teams()
RETURNS TABLE(id uuid, name text, department text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT id, name, department FROM public.teams WHERE is_active ORDER BY name;
$$;
REVOKE EXECUTE ON FUNCTION public.list_active_teams() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_active_teams() TO authenticated;
