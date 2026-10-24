-- ============================================================================
-- ROLLBACK / pre-migration snapshot for PROPOSED_isolation_migration.sql
-- Captured from the live TaskOra DB this session (pg_get_functiondef / pg_policies
-- / pg_get_viewdef). Run TOP-TO-BOTTOM to revert the isolation migration.
-- apply_migration is NOT guaranteed to be a single atomic transaction across
-- stages, so this file is the authoritative revert path. Run inside BEGIN/COMMIT.
-- ============================================================================
BEGIN;

-- 1) Restore admin policy predicates (were: get_my_role() = 'admin'::user_role) ----
ALTER POLICY "Admin full on profiles"                   ON public.profiles                      USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on teams"                      ON public.teams                         USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "admin_all"                                ON public.team_privileges               USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_assignees"             ON public.task_assignees                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_approvals"             ON public.task_approvals                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_comments"              ON public.task_comments                 USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_attachments"           ON public.task_attachments              USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin reads all audit logs"               ON public.task_audit_log                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_mentions"              ON public.task_mentions                 USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_boards"                ON public.task_boards                   USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on task_board_columns"         ON public.task_board_columns            USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on events"                     ON public.events                        USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on event_attendees"            ON public.event_attendees               USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on event_attachments"          ON public.event_attachments             USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on attendance"                 ON public.attendance                    USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on crm_entries"                ON public.crm_entries                   USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on crm_payments"               ON public.crm_payments                  USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin only on expenses"                   ON public.expenses                      USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on expense_categories"         ON public.expense_categories            USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin only on penalties"                  ON public.penalties                     USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on penalty_types"              ON public.penalty_types                 USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on client_profiles"            ON public.client_profiles               USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on client_task_visibility"     ON public.client_task_visibility        USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on client_task_column_visibility" ON public.client_task_column_visibility USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on custom_tables"              ON public.custom_tables                 USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on custom_columns"             ON public.custom_columns                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on custom_rows"                ON public.custom_rows                   USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on custom_cell_values"         ON public.custom_cell_values            USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on column_status_options"      ON public.column_status_options         USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on table_permissions"          ON public.table_permissions             USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on table_views"                ON public.table_views                   USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin reads all cell audit logs"          ON public.cell_audit_log                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on notes"                      ON public.notes                         USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on note_tags"                  ON public.note_tags                     USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on note_shares"                ON public.note_shares                   USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on note_links"                 ON public.note_links                    USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on note_attachments"           ON public.note_attachments              USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin reads all note logs"                ON public.note_audit_log                USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on rooms"                      ON public.rooms                         USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin full on room_bookings"              ON public.room_bookings                 USING (get_my_role() = 'admin'::user_role);
ALTER POLICY "Admin reads ai_interactions"              ON public.ai_interactions               USING (get_my_role() = 'admin'::user_role);

ALTER POLICY "app_settings_admin_write" ON public.app_settings
  USING  ((EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::user_role)))))
  WITH CHECK ((EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::user_role)))));
ALTER POLICY "user_priv_admin_all" ON public.user_privileges
  USING  ((EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::user_role)))))
  WITH CHECK ((EXISTS ( SELECT 1 FROM profiles p WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::user_role)))));
ALTER POLICY "tasks_admin_all" ON public.tasks
  USING  ((( SELECT profiles.role FROM profiles WHERE (profiles.id = auth.uid())) = 'admin'::user_role))
  WITH CHECK ((( SELECT profiles.role FROM profiles WHERE (profiles.id = auth.uid())) = 'admin'::user_role));

ALTER POLICY "attendance_reminders_read" ON public.attendance_reminders
  USING (((employee_id = auth.uid()) OR (EXISTS ( SELECT 1 FROM profiles me WHERE ((me.id = auth.uid()) AND (me.role = 'admin'::user_role)))) OR (EXISTS ( SELECT 1 FROM (profiles me JOIN profiles emp ON ((emp.id = attendance_reminders.employee_id))) WHERE ((me.id = auth.uid()) AND (me.role = 'manager'::user_role) AND (me.team_id IS NOT NULL) AND (me.team_id = emp.team_id))))));
ALTER POLICY "System sends notifications" ON public.notifications
  WITH CHECK (((get_my_role() = 'admin'::user_role) OR (auth.role() = 'service_role'::text)));
ALTER POLICY "System inserts audit logs" ON public.task_audit_log
  WITH CHECK (((get_my_role() = 'admin'::user_role) OR (auth.role() = 'service_role'::text)));
ALTER POLICY "System inserts cell audit logs" ON public.cell_audit_log
  WITH CHECK (((auth.role() = 'service_role'::text) OR (get_my_role() = 'admin'::user_role)));
ALTER POLICY "System and triggers insert note logs" ON public.note_audit_log
  WITH CHECK (((auth.role() = 'service_role'::text) OR (get_my_role() = 'admin'::user_role) OR (actor_id = auth.uid())));
ALTER POLICY "Editable cells follow permissions" ON public.custom_cell_values
  WITH CHECK (((get_my_role() = ANY (ARRAY['admin'::user_role, 'employee'::user_role])) AND (row_id IN ( SELECT custom_rows.id FROM custom_rows WHERE (custom_rows.table_id IN ( SELECT tp.table_id FROM table_permissions tp WHERE ((tp.can_edit_rows = true) AND (((tp.grantee_type = 'profile'::permission_grantee_type) AND (tp.grantee_id = auth.uid())) OR ((tp.grantee_type = 'team'::permission_grantee_type) AND (tp.grantee_id IN ( SELECT profiles.team_id FROM profiles WHERE (profiles.id = auth.uid())))))))))))));
ALTER POLICY "Editable cells update follow permissions" ON public.custom_cell_values
  USING (((get_my_role() = ANY (ARRAY['admin'::user_role, 'employee'::user_role])) AND (row_id IN ( SELECT custom_rows.id FROM custom_rows WHERE (custom_rows.table_id IN ( SELECT tp.table_id FROM table_permissions tp WHERE ((tp.can_edit_rows = true) AND (((tp.grantee_type = 'profile'::permission_grantee_type) AND (tp.grantee_id = auth.uid())) OR ((tp.grantee_type = 'team'::permission_grantee_type) AND (tp.grantee_id IN ( SELECT profiles.team_id FROM profiles WHERE (profiles.id = auth.uid())))))))))))));
ALTER POLICY "Visible columns — read" ON public.custom_columns
  USING (((table_id IN ( SELECT get_accessible_table_ids.table_id FROM get_accessible_table_ids(auth.uid()) get_accessible_table_ids(table_id))) AND ((get_my_role() = 'admin'::user_role) OR ((is_admin_only = false) AND ((get_my_role() <> 'employee'::user_role) OR (is_hidden_from_employee = false)) AND ((get_my_role() <> 'client'::user_role) OR (is_hidden_from_client = false))))));

-- 2) Restore guard trigger function (pre-migration definition) -------------------
CREATE OR REPLACE FUNCTION public.guard_profile_privileged_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.id = auth.uid()
     AND (NEW.role IS DISTINCT FROM OLD.role OR NEW.status IS DISTINCT FROM OLD.status OR NEW.team_id IS DISTINCT FROM OLD.team_id)
     AND coalesce(auth.role(), '') <> 'service_role'
     AND public.get_my_role() <> 'admin'::user_role
  THEN
    RAISE EXCEPTION 'You may not change your own role, status, or team assignment.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;

-- 3) Restore get_profile_by_email (pre-migration: SETOF profiles, no auth gate) --
CREATE OR REPLACE FUNCTION public.get_profile_by_email(user_email text)
RETURNS SETOF profiles LANGUAGE sql SECURITY DEFINER
AS $$
  select p.* from profiles p join auth.users u on u.id = p.id
  where lower(u.email) = lower(user_email) limit 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_profile_by_email(text) TO anon;  -- restore prior grant if it existed

-- 4) Restore init_client_task_visibility (pre-migration: no caller check) --------
CREATE OR REPLACE FUNCTION public.init_client_task_visibility(p_team_id uuid, p_client_id uuid, p_admin_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.client_task_visibility (team_id, client_id, can_see_tasks_section, can_see_completed_tasks, can_see_cancelled_tasks, can_see_task_comments, can_see_task_files, can_approve_tasks, configured_by)
  VALUES (p_team_id, p_client_id, true, true, false, true, true, true, p_admin_id)
  ON CONFLICT (team_id, client_id) DO NOTHING RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 5) Restore views to definer semantics (pre-migration: security_invoker unset) --
ALTER VIEW public.tasks_employee_view     RESET (security_invoker);
ALTER VIEW public.admin_tables_overview   RESET (security_invoker);
ALTER VIEW public.client_task_config_view RESET (security_invoker);
ALTER VIEW public.tasks_client_view       RESET (security_invoker);
ALTER VIEW public.crm_client_view         RESET (security_invoker);

-- 6) Drop the super-admin additions (after policies no longer reference them) ----
DROP FUNCTION IF EXISTS public.is_global_admin();
ALTER TABLE public.profiles DROP COLUMN IF EXISTS is_super_admin;

COMMIT;
