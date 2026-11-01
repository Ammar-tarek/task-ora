-- ============================================================================
-- PROPOSED (NOT APPLIED) — Task Handoff: definition lock, receiving-only write,
-- assignment control, delete lock, and the sender SELECT-only policy.
-- Needs explicit approval. APPLY ORDER: PROPOSED_handoff_rpcs.sql FIRST (its RPC
-- sets the `app.task_handoff` transaction GUC these triggers read), then this.
--
-- MODEL (user-approved 2026-10-31 — Option A, Direct Transfer):
--   A task is "transferred" once tasks.handoff_from_team_id IS NOT NULL (set by
--   handoff_task). From that point:
--     * Only the CURRENT (receiving) team may WRITE at all, and only to
--       {status, completion_percentage, updated_at}. The sender (and anyone
--       whose team <> tasks.team_id) gets NO write — not even status/progress.
--     * The definition (title, description, priority, deadline, client, cost,
--       financial fields, team/department, …) is locked by DEFAULT-DENY.
--     * Assignment is managed ONLY by the receiving team's MANAGER, and only to
--       employees who BELONG to the receiving team.
--     * The task cannot be deleted or re-transferred by a department.
--     * A global admin (or trusted service_role) overrides everything.
--
-- DESIGN NOTES (security review):
--  * DEFAULT-DENY definition lock. It does NOT enumerate "protected" columns
--    (an allow-list of locked columns silently misses new/renamed ones). It
--    ALLOWS exactly {status, completion_percentage, updated_at} and rejects a
--    diff in ANY other column. New columns are locked by default.
--  * RECEIVING-ONLY write. On a transferred task, a writer whose my_team_id()
--    <> NEW.team_id is rejected outright. This closes the hole where the sender
--    who CREATED the task would otherwise keep UPDATE via the created_by RLS
--    policy and could still move status/progress. Sender = view only.
--  * GUC IS BOUNDED. handoff_task sets app.task_handoff='1' (txn-local) so its
--    own plumbing writes (team_id + handoff_*) pass. That flag widens the
--    allow-set ONLY to those plumbing columns and never unlocks a definition
--    field; it is unreachable by end users (see handoff_rpcs header).
--  * SECURITY DEFINER + SET search_path='public'; mirrors the guard_task_*
--    family. Trigger functions are not granted to API roles.
-- Additive + reversible. No change to existing data or unrelated triggers.
--
-- INTERPLAY WITH EXISTING APPLIED TRIGGERS (verified live):
--  * trg_guard_task_employee_fields (guard_task_employee_fields) forbade ALL
--    employees from changing completion_percentage (allowed only due_date +
--    status). Per DECISION C1=B this file REPLACES that function (§5) so that an
--    employee WHO IS ASSIGNED TO A TRANSFERRED TASK may also change
--    completion_percentage — and ONLY that employee, ONLY on a transferred task.
--    Every other employee/task is unchanged (completion still blocked). This is
--    the ONE existing trigger this change modifies; it is a strict, scoped
--    widening, verified below and in HANDOFF_DIRECT_TRANSFER_REVIEW.md §Decisions.
--  * trg_guard_task_status_transition / trg_guard_task_payment_status remain in
--    force, UNCHANGED, and still apply on top of this lock.
-- ============================================================================

-- 1) Definition lock + receiving-only write (BEFORE UPDATE on tasks). ---------
CREATE OR REPLACE FUNCTION public.guard_transferred_task_definition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_handoff_ctx boolean := COALESCE(current_setting('app.task_handoff', true), '') = '1';
  v_new jsonb;
  v_old jsonb;
BEGIN
  -- Not transferred yet → normal rules (other guards + RLS still apply). The
  -- handoff_task transfer write itself hits this branch (OLD.handoff_from_team_id
  -- is NULL on the first transfer), so the transfer passes.
  IF OLD.handoff_from_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Global admin / trusted service-role → full control (matches tasks_admin_all).
  IF public.is_global_admin() OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- RECEIVING-ONLY: outside the handoff RPC, only a writer who belongs to the
  -- task's CURRENT (receiving) team may change anything at all. The sending
  -- department — including the original creator, who still satisfies the
  -- created_by UPDATE policy — is view-only on a transferred task.
  IF NOT v_handoff_ctx AND public.my_team_id() IS DISTINCT FROM NEW.team_id THEN
    RAISE EXCEPTION 'This task was transferred to another department; your department can only view it.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- DEFAULT-DENY: only status, completion_percentage, updated_at may differ.
  v_new := to_jsonb(NEW) - 'status' - 'completion_percentage' - 'updated_at';
  v_old := to_jsonb(OLD) - 'status' - 'completion_percentage' - 'updated_at';

  -- Inside the handoff RPC only, also allow the PLUMBING columns to move
  -- (team_id + handoff_*). This never unlocks a definition field.
  IF v_handoff_ctx THEN
    v_new := v_new - 'team_id' - 'handoff_to_team_id' - 'handoff_from_team_id'
                   - 'handoff_by' - 'handoff_note';
    v_old := v_old - 'team_id' - 'handoff_to_team_id' - 'handoff_from_team_id'
                   - 'handoff_by' - 'handoff_note';
  END IF;

  IF v_new IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION 'This task was transferred to another department; its definition is locked. Only status and progress can change.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_transferred_task_definition ON public.tasks;
CREATE TRIGGER trg_guard_transferred_task_definition
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_transferred_task_definition();

-- 2) Block DELETE of a transferred task by a department (admin/service only). -
CREATE OR REPLACE FUNCTION public.guard_transferred_task_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.handoff_from_team_id IS NOT NULL
     AND auth.role() <> 'service_role'
     AND NOT public.is_global_admin() THEN
    RAISE EXCEPTION 'This task was transferred and cannot be deleted by a department; ask an admin.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_transferred_task_delete ON public.tasks;
CREATE TRIGGER trg_guard_transferred_task_delete
  BEFORE DELETE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_transferred_task_delete();

-- 3) Assignment control on a transferred task (BEFORE INS/UPD/DEL task_assignees).
--    handoff_task clears assignees inside its RPC (GUC set) so that passes. The
--    RECEIVING team's manager may (re)assign to employees of the RECEIVING team;
--    everyone else (the sender, employees, other teams) is rejected.
CREATE OR REPLACE FUNCTION public.guard_transferred_task_assignees()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_task uuid := COALESCE(NEW.task_id, OLD.task_id);
  v_team uuid;
  v_from uuid;
BEGIN
  SELECT team_id, handoff_from_team_id INTO v_team, v_from
    FROM public.tasks WHERE id = v_task;

  -- Handoff RPC plumbing / trusted service / global admin → allow.
  IF COALESCE(current_setting('app.task_handoff', true), '') = '1'
     OR auth.role() = 'service_role'
     OR public.is_global_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Not a transferred task → this guard does not interfere (normal RLS governs).
  IF v_from IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Transferred task: only the RECEIVING team's MANAGER may manage assignment.
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

DROP TRIGGER IF EXISTS trg_guard_transferred_task_assignees ON public.task_assignees;
CREATE TRIGGER trg_guard_transferred_task_assignees
  BEFORE INSERT OR UPDATE OR DELETE ON public.task_assignees
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_transferred_task_assignees();

-- 4) Sender SELECT-only visibility for the WHOLE sending department. ----------
-- After a direct transfer tasks.team_id = receiving team, so NO member of the
-- sending team matches manager_team_tasks / tasks_employee_* any more and the
-- task vanishes from their view. This additive SELECT policy returns view/track
-- access to EVERY staff member of the sending team (manager AND employees),
-- scoped by handoff_from_team_id = my_team_id(). There is NO companion
-- UPDATE/DELETE/INSERT policy, so the sending department is strictly read-only:
-- the receiving-only write guard (§1) rejects any sender UPDATE, the assignment
-- guard (§3) rejects any sender (re)assign, the delete guard (§2) blocks sender
-- DELETE, and handoff_task (§RPC) blocks sender re-transfer.
-- (Clients hold no team, so my_team_id() is NULL and they match nothing here.)
DROP POLICY IF EXISTS tasks_sender_view ON public.tasks;
CREATE POLICY tasks_sender_view ON public.tasks
  FOR SELECT TO authenticated
  USING (handoff_from_team_id IS NOT NULL
         AND handoff_from_team_id = public.my_team_id());

-- NOTE (inert, left in place): the applied SELECT policy "tasks_manager_waiting"
-- (is_manager() AND handoff_to_team_id = my_team_id()) belonged to the old
-- pending model. The direct model never sets handoff_to_team_id, so the policy
-- now matches nothing and is harmless. Optional cleanup (a live change — do NOT
-- run without separate approval):
--   DROP POLICY IF EXISTS tasks_manager_waiting ON public.tasks;

-- 5) C1=B — assigned employee may move completion_percentage on a TRANSFERRED
--    task. Full REPLACE of the applied guard_task_employee_fields; the ONLY
--    change vs the live function is the completion_percentage clause, which is
--    now skipped when the caller is an assignee of a transferred task. All other
--    columns stay locked for employees, and all other tasks are unchanged.
CREATE OR REPLACE FUNCTION public.guard_task_employee_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  -- True only for an employee who is assigned to THIS task AND the task has been
  -- transferred (handoff_from_team_id set). Scopes the completion carve-out to
  -- exactly the receiving assignee on a handed-off task (DECISION C1=B).
  v_allow_completion boolean := (OLD.handoff_from_team_id IS NOT NULL)
    AND EXISTS (
      SELECT 1 FROM public.task_assignees
      WHERE task_id = NEW.id AND profile_id = auth.uid()
    )
    -- caller must still BELONG to the receiving department (profiles.team_id =
    -- the task's current team). Blocks a stale assignee whose team moved away.
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND team_id = NEW.team_id
    );
BEGIN
  IF public.is_global_admin() OR auth.role() = 'service_role'
     OR public.get_my_role() <> 'employee' THEN
    RETURN NEW;
  END IF;

  IF NEW.priority              IS DISTINCT FROM OLD.priority
     OR NEW.cost               IS DISTINCT FROM OLD.cost
     OR NEW.payment_status     IS DISTINCT FROM OLD.payment_status
     OR (NOT v_allow_completion
         AND NEW.completion_percentage IS DISTINCT FROM OLD.completion_percentage)
     OR NEW.team_id            IS DISTINCT FROM OLD.team_id
     OR NEW.client_id          IS DISTINCT FROM OLD.client_id
     OR NEW.hidden_from_client IS DISTINCT FROM OLD.hidden_from_client
     OR NEW.title              IS DISTINCT FROM OLD.title
     OR NEW.description        IS DISTINCT FROM OLD.description
     OR NEW.board_id           IS DISTINCT FROM OLD.board_id
     OR NEW.board_column_id    IS DISTINCT FROM OLD.board_column_id
     OR NEW.parent_task_id     IS DISTINCT FROM OLD.parent_task_id
     OR NEW.is_template        IS DISTINCT FROM OLD.is_template
  THEN
    RAISE EXCEPTION 'Employees may edit only the task deadline.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;
-- Trigger trg_guard_task_employee_fields already exists and points at this
-- function (CREATE OR REPLACE keeps the existing trigger binding) — no trigger
-- DDL needed. The function keeps its existing grants (not part of the API).

-- Trigger functions are invoked by their triggers, never called directly; deny
-- the implicit PUBLIC execute grant so they are not part of the API surface.
REVOKE EXECUTE ON FUNCTION public.guard_transferred_task_definition() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_transferred_task_delete()     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_transferred_task_assignees()  FROM PUBLIC, anon, authenticated;

-- ── VALIDATION (after apply, on a branch) ───────────────────────────────────
-- On a transferred task (handoff_from_team_id = SRC, team_id = DST):
--  RECEIVING manager (team=DST):
--    INSERT INTO task_assignees(task_id,profile_id) VALUES('<t>','<DST employee>'); -- ok
--    INSERT INTO task_assignees(task_id,profile_id) VALUES('<t>','<SRC employee>'); -- ERROR (dept)
--    UPDATE tasks SET status='in_progress' WHERE id='<t>';     -- ok (track)
--    UPDATE tasks SET title='x'            WHERE id='<t>';     -- ERROR (definition locked)
--    DELETE FROM tasks WHERE id='<t>';                          -- ERROR (delete locked)
--    SELECT handoff_task('<t>','<other>');                      -- ERROR (re-transfer)
--  RECEIVING assigned employee (team=DST): UPDATE status -> ok;
--    UPDATE completion_percentage -> ok (C1=B carve-out); title/cost -> ERROR.
--  RECEIVING employee NOT assigned: completion_percentage -> ERROR (still locked).
--  ANY employee on a NON-transferred task: completion_percentage -> ERROR (unchanged).
--  SENDING manager (team=SRC): SELECT -> visible; any UPDATE/assign/DELETE -> ERROR.
--  SENDING employee, ANY (creator or not): SELECT -> visible (whole-dept policy);
--    UPDATE status/anything -> ERROR (receiving-only); assign/DELETE -> ERROR.
--  GLOBAL ADMIN: all of the above succeed (override). Never-transferred task: unaffected.

-- ── Rollback (removes ONLY what this file introduces) ───────────────────────
--   -- Restore guard_task_employee_fields to its pre-C1 body (the version in
--   -- PROPOSED_task_assignment_response.sql / live snapshot): re-run that file's
--   -- CREATE OR REPLACE of guard_task_employee_fields (completion_percentage
--   -- unconditionally locked). The trigger binding is unchanged.
--   DROP POLICY   IF EXISTS tasks_sender_view ON public.tasks;
--   DROP TRIGGER  IF EXISTS trg_guard_transferred_task_assignees ON public.task_assignees;
--   DROP FUNCTION IF EXISTS public.guard_transferred_task_assignees();
--   DROP TRIGGER  IF EXISTS trg_guard_transferred_task_delete ON public.tasks;
--   DROP FUNCTION IF EXISTS public.guard_transferred_task_delete();
--   DROP TRIGGER  IF EXISTS trg_guard_transferred_task_definition ON public.tasks;
--   DROP FUNCTION IF EXISTS public.guard_transferred_task_definition();
