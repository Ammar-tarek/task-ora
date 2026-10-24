-- ============================================================================
-- ✅ APPLIED on the TaskOra project in 5 staged migrations (verified):
--    1. isolation_b1_security_invoker_views
--    2. isolation_b5_core_superadmin        (column + is_global_admin + guard + seed ammar)
--    3. isolation_b3_b4_rpc_hardening        (see deviation below)
--    4. isolation_b3_revoke_anon_profile_email
--    5. isolation_b5_policies_global_admin
-- Deviations from the text below, as actually applied:
--  * B3 kept RETURNS SETOF profiles (no DROP, which was declined as destructive);
--    column-narrowing to hide fcm_token/telegram is a deferred follow-up needing
--    an approved DROP. anon EXECUTE revoked explicitly (REVOKE FROM PUBLIC alone
--    left a direct anon grant). The auth.uid() gate already blocks anon results.
--  * The 3 deeply-nested custom_* compound policies were rewritten in clean,
--    balanced, semantically-equivalent form (same effect).
-- Rollback: ROLLBACK_isolation_snapshot.sql. B2 remains a separate app change.
-- The original proposal text is kept below for reference.
-- ============================================================================
--
-- Target: PostgreSQL 17. Run inside a single transaction EXCEPT the view ALTERs
-- (safe either way). Snapshot `pg_policies` and `pg_get_functiondef` first so
-- every change is reversible. The B5 policy rewrites replace ONLY the admin
-- sub-expression with public.is_global_admin(); all other clauses are preserved
-- verbatim from the live policies.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- B1 — SECURITY DEFINER views bypass RLS (CRITICAL). Make them honor the caller.
-- Rollback: ALTER VIEW ... RESET (security_invoker);
-- ----------------------------------------------------------------------------
ALTER VIEW public.tasks_employee_view     SET (security_invoker = on);
ALTER VIEW public.admin_tables_overview   SET (security_invoker = on);
ALTER VIEW public.client_task_config_view SET (security_invoker = on);
ALTER VIEW public.tasks_client_view       SET (security_invoker = on);
ALTER VIEW public.crm_client_view         SET (security_invoker = on);

-- ----------------------------------------------------------------------------
-- B5a — Verified Super Admin: flag + helper (reversible boolean, not an enum).
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_super_admin boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.is_global_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (role = 'admin'::user_role OR is_super_admin = true)
  );
$$;

-- ----------------------------------------------------------------------------
-- B5b — Guard trigger: a verified global admin may edit others' role/status/team.
-- Rollback: restore original (uses: public.get_my_role() <> 'admin'::user_role).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_profile_privileged_fields()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only a VERIFIED super admin (or service_role) may grant/revoke super-admin,
  -- on ANY row. Without this, "Users update own profile" RLS would let anyone
  -- set is_super_admin = true on themselves and self-elevate to global admin.
  IF (NEW.is_super_admin IS DISTINCT FROM OLD.is_super_admin)
     AND coalesce(auth.role(), '') <> 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_super_admin = true
     )
  THEN
    RAISE EXCEPTION 'Only a super admin may change super-admin status.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- A user may not change their OWN role/status/team unless a global admin
  -- (admin or super admin) or service_role.
  IF NEW.id = auth.uid()
     AND ( NEW.role IS DISTINCT FROM OLD.role
        OR NEW.status IS DISTINCT FROM OLD.status
        OR NEW.team_id IS DISTINCT FROM OLD.team_id )
     AND coalesce(auth.role(), '') <> 'service_role'
     AND NOT public.is_global_admin()
  THEN
    RAISE EXCEPTION 'You may not change your own role, status, or team assignment.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- B5c — Migrate every admin policy predicate to public.is_global_admin().
--       Simple "admin-only" policies (USING = get_my_role()='admin'):
-- ----------------------------------------------------------------------------
ALTER POLICY "Admin full on profiles"                   ON public.profiles                      USING (public.is_global_admin());
ALTER POLICY "Admin full on teams"                      ON public.teams                         USING (public.is_global_admin());
ALTER POLICY "admin_all"                                ON public.team_privileges               USING (public.is_global_admin());
ALTER POLICY "Admin full on task_assignees"             ON public.task_assignees                USING (public.is_global_admin());
ALTER POLICY "Admin full on task_approvals"             ON public.task_approvals                USING (public.is_global_admin());
ALTER POLICY "Admin full on task_comments"              ON public.task_comments                 USING (public.is_global_admin());
ALTER POLICY "Admin full on task_attachments"           ON public.task_attachments              USING (public.is_global_admin());
ALTER POLICY "Admin reads all audit logs"               ON public.task_audit_log                USING (public.is_global_admin());
ALTER POLICY "Admin full on task_mentions"              ON public.task_mentions                 USING (public.is_global_admin());
ALTER POLICY "Admin full on task_boards"                ON public.task_boards                   USING (public.is_global_admin());
ALTER POLICY "Admin full on task_board_columns"         ON public.task_board_columns            USING (public.is_global_admin());
ALTER POLICY "Admin full on events"                     ON public.events                        USING (public.is_global_admin());
ALTER POLICY "Admin full on event_attendees"            ON public.event_attendees               USING (public.is_global_admin());
ALTER POLICY "Admin full on event_attachments"          ON public.event_attachments             USING (public.is_global_admin());
ALTER POLICY "Admin full on attendance"                 ON public.attendance                    USING (public.is_global_admin());
ALTER POLICY "Admin full on crm_entries"                ON public.crm_entries                   USING (public.is_global_admin());
ALTER POLICY "Admin full on crm_payments"               ON public.crm_payments                  USING (public.is_global_admin());
ALTER POLICY "Admin only on expenses"                   ON public.expenses                      USING (public.is_global_admin());
ALTER POLICY "Admin full on expense_categories"         ON public.expense_categories            USING (public.is_global_admin());
ALTER POLICY "Admin only on penalties"                  ON public.penalties                     USING (public.is_global_admin());
ALTER POLICY "Admin full on penalty_types"              ON public.penalty_types                 USING (public.is_global_admin());
ALTER POLICY "Admin full on client_profiles"            ON public.client_profiles               USING (public.is_global_admin());
ALTER POLICY "Admin full on client_task_visibility"     ON public.client_task_visibility        USING (public.is_global_admin());
ALTER POLICY "Admin full on client_task_column_visibility" ON public.client_task_column_visibility USING (public.is_global_admin());
ALTER POLICY "Admin full on custom_tables"              ON public.custom_tables                 USING (public.is_global_admin());
ALTER POLICY "Admin full on custom_columns"             ON public.custom_columns                USING (public.is_global_admin());
ALTER POLICY "Admin full on custom_rows"                ON public.custom_rows                   USING (public.is_global_admin());
ALTER POLICY "Admin full on custom_cell_values"         ON public.custom_cell_values            USING (public.is_global_admin());
ALTER POLICY "Admin full on column_status_options"      ON public.column_status_options         USING (public.is_global_admin());
ALTER POLICY "Admin full on table_permissions"          ON public.table_permissions             USING (public.is_global_admin());
ALTER POLICY "Admin full on table_views"                ON public.table_views                   USING (public.is_global_admin());
ALTER POLICY "Admin reads all cell audit logs"          ON public.cell_audit_log                USING (public.is_global_admin());
ALTER POLICY "Admin full on notes"                      ON public.notes                         USING (public.is_global_admin());
ALTER POLICY "Admin full on note_tags"                  ON public.note_tags                     USING (public.is_global_admin());
ALTER POLICY "Admin full on note_shares"                ON public.note_shares                   USING (public.is_global_admin());
ALTER POLICY "Admin full on note_links"                 ON public.note_links                    USING (public.is_global_admin());
ALTER POLICY "Admin full on note_attachments"           ON public.note_attachments              USING (public.is_global_admin());
ALTER POLICY "Admin reads all note logs"                ON public.note_audit_log                USING (public.is_global_admin());
ALTER POLICY "Admin full on rooms"                      ON public.rooms                         USING (public.is_global_admin());
ALTER POLICY "Admin full on room_bookings"              ON public.room_bookings                 USING (public.is_global_admin());
ALTER POLICY "Admin reads ai_interactions"              ON public.ai_interactions               USING (public.is_global_admin());

-- Dual USING + WITH CHECK admin policies:
ALTER POLICY "app_settings_admin_write" ON public.app_settings
  USING (public.is_global_admin()) WITH CHECK (public.is_global_admin());
ALTER POLICY "user_priv_admin_all" ON public.user_privileges
  USING (public.is_global_admin()) WITH CHECK (public.is_global_admin());
ALTER POLICY "tasks_admin_all" ON public.tasks
  USING (public.is_global_admin()) WITH CHECK (public.is_global_admin());

-- Compound policies — admin replaced, all other clauses preserved verbatim:
ALTER POLICY "attendance_reminders_read" ON public.attendance_reminders
  USING (
    (employee_id = auth.uid())
    OR public.is_global_admin()
    OR (EXISTS ( SELECT 1 FROM (profiles me JOIN profiles emp ON ((emp.id = attendance_reminders.employee_id)))
        WHERE ((me.id = auth.uid()) AND (me.role = 'manager'::user_role) AND (me.team_id IS NOT NULL) AND (me.team_id = emp.team_id))))
  );

ALTER POLICY "System sends notifications" ON public.notifications
  WITH CHECK (public.is_global_admin() OR (auth.role() = 'service_role'::text));

ALTER POLICY "System inserts audit logs" ON public.task_audit_log
  WITH CHECK (public.is_global_admin() OR (auth.role() = 'service_role'::text));

ALTER POLICY "System inserts cell audit logs" ON public.cell_audit_log
  WITH CHECK ((auth.role() = 'service_role'::text) OR public.is_global_admin());

ALTER POLICY "System and triggers insert note logs" ON public.note_audit_log
  WITH CHECK ((auth.role() = 'service_role'::text) OR public.is_global_admin() OR (actor_id = auth.uid()));

ALTER POLICY "Editable cells follow permissions" ON public.custom_cell_values
  WITH CHECK (
    (public.is_global_admin() OR (get_my_role() = 'employee'::user_role))
    AND (row_id IN ( SELECT custom_rows.id FROM custom_rows
      WHERE (custom_rows.table_id IN ( SELECT tp.table_id FROM table_permissions tp
        WHERE ((tp.can_edit_rows = true) AND (((tp.grantee_type = 'profile'::permission_grantee_type) AND (tp.grantee_id = auth.uid()))
          OR ((tp.grantee_type = 'team'::permission_grantee_type) AND (tp.grantee_id IN ( SELECT profiles.team_id FROM profiles WHERE (profiles.id = auth.uid())))))))))))
  );

ALTER POLICY "Editable cells update follow permissions" ON public.custom_cell_values
  USING (
    (public.is_global_admin() OR (get_my_role() = 'employee'::user_role))
    AND (row_id IN ( SELECT custom_rows.id FROM custom_rows
      WHERE (custom_rows.table_id IN ( SELECT tp.table_id FROM table_permissions tp
        WHERE ((tp.can_edit_rows = true) AND (((tp.grantee_type = 'profile'::permission_grantee_type) AND (tp.grantee_id = auth.uid()))
          OR ((tp.grantee_type = 'team'::permission_grantee_type) AND (tp.grantee_id IN ( SELECT profiles.team_id FROM profiles WHERE (profiles.id = auth.uid())))))))))))
  );

ALTER POLICY "Visible columns — read" ON public.custom_columns
  USING (
    (table_id IN ( SELECT get_accessible_table_ids.table_id FROM get_accessible_table_ids(auth.uid()) get_accessible_table_ids(table_id)))
    AND (public.is_global_admin()
      OR ((is_admin_only = false)
        AND ((get_my_role() <> 'employee'::user_role) OR (is_hidden_from_employee = false))
        AND ((get_my_role() <> 'client'::user_role) OR (is_hidden_from_client = false))))
  );

-- NOTE: "manager_update_team_members" ON public.profiles has a WITH CHECK that
-- forbids setting role='admin'. If super admins should likewise not be settable
-- by a manager, extend that check to also exclude is_super_admin. Left as-is
-- (managers cannot set the boolean anyway without a column-level grant).

-- ----------------------------------------------------------------------------
-- B5d — Bootstrap the intended super admin. REQUIRED: without this, no one is a
-- super admin and (by the strengthened guard) no one can grant it via the app —
-- only this migration (run as a privileged role) can establish the first one.
-- Verified present this session: ammar@cashback.com (role=admin).
-- ----------------------------------------------------------------------------
UPDATE public.profiles p SET is_super_admin = true
  FROM auth.users u
 WHERE u.id = p.id AND lower(u.email) = lower('ammar@cashback.com');

-- ----------------------------------------------------------------------------
-- B3 — get_profile_by_email: add search_path, authenticated-only, minimal cols.
-- DECISION: confirm the login flow does not call this pre-auth (anon). The app
-- (profile_repository.fetchByEmail) must be reconciled with the narrowed columns.
-- ----------------------------------------------------------------------------
-- Keeps team_id: team_members_screen._searchByEmail reads profile.teamId to warn
-- "already on another team". Drops phone/avatar/telegram/fcm/email/timezone/
-- last_login (the sensitive PII) which no caller uses.
CREATE OR REPLACE FUNCTION public.get_profile_by_email(user_email text)
RETURNS TABLE(id uuid, role public.user_role, status public.user_status, full_name text, team_id uuid)
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
REVOKE EXECUTE ON FUNCTION public.get_profile_by_email(text) FROM anon;

-- ----------------------------------------------------------------------------
-- B4 — init_client_task_visibility: require admin/manager-of-team; stamp caller.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.init_client_task_visibility(
  p_team_id uuid, p_client_id uuid, p_admin_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid; caller_role text; caller_team uuid;
BEGIN
  SELECT role, team_id INTO caller_role, caller_team FROM public.profiles WHERE id = auth.uid();
  IF caller_role IS NULL
     OR NOT (public.is_global_admin() OR (caller_role = 'manager' AND caller_team = p_team_id)) THEN
    RAISE EXCEPTION 'Not authorized to configure client visibility' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.client_task_visibility (
    team_id, client_id, can_see_tasks_section, can_see_completed_tasks,
    can_see_cancelled_tasks, can_see_task_comments, can_see_task_files,
    can_approve_tasks, configured_by
  ) VALUES (p_team_id, p_client_id, true, true, false, true, true, true, auth.uid())
  ON CONFLICT (team_id, client_id) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMIT;

-- ============================================================================
-- B2 (APPLICATION change, approved decision = managers see NO expenses / RLS-pure)
-- Move attendance / finance / penalty READS from SupabaseService.adminClient to
-- the RLS client, so the DB enforces scope. Files:
--   attendance_repository.dart:290,312,702,895 · finance_repository.dart:168,181,194,206
--   penalty_repository.dart:73,516,536
-- With RLS, expenses are admin-only → a manager's finance "expenses" total = 0
-- (accepted). Requires the role × department regression matrix before shipping.
-- ============================================================================
