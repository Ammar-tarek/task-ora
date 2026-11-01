-- ============================================================================
-- FIX (NOT APPLIED) — Let an assignee accept/reject their OWN assignment on a
-- TRANSFERRED task.
--
-- The field-lock guard guard_transferred_task_assignees only allowed the
-- receiving team's MANAGER (or a global admin) to touch task_assignees on a
-- transferred task. So when an EMPLOYEE accepts/rejects via respond_to_assignment
-- (which updates/deletes their own row), the guard raised insufficient_privilege
-- -> 403 / error 42501.
--
-- This adds one exception: the assignee may change THEIR OWN row (they can only
-- ever touch their own row, so it is safe). Everything else is unchanged.
-- Apply in the Supabase SQL Editor.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.guard_transferred_task_assignees()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_task uuid := COALESCE(NEW.task_id, OLD.task_id);
  v_team uuid;
  v_from uuid;
BEGIN
  SELECT team_id, handoff_from_team_id INTO v_team, v_from
    FROM public.tasks WHERE id = v_task;

  -- Handoff RPC plumbing / trusted service / global admin -> allow.
  IF COALESCE(current_setting('app.task_handoff', true), '') = '1'
     OR auth.role() = 'service_role'
     OR public.is_global_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Not a transferred task -> this guard does not interfere.
  IF v_from IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- The ASSIGNEE may accept/reject their OWN assignment on a transferred task
  -- (respond_to_assignment updates their own response row, or removes it on
  -- reject). They can only ever touch their own row, so this is safe.
  IF COALESCE(NEW.profile_id, OLD.profile_id) = auth.uid() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Otherwise: only the RECEIVING team's MANAGER may manage assignment.
  IF NOT (public.is_manager() AND public.my_team_id() = v_team) THEN
    RAISE EXCEPTION 'Only the receiving department''s manager may assign this transferred task.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- The assignee must BELONG to the receiving team (INSERT/UPDATE).
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = NEW.profile_id AND team_id = v_team
    ) THEN
      RAISE EXCEPTION 'Assignee must belong to the receiving department.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;
