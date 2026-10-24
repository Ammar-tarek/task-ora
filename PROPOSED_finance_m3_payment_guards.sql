-- ============================================================================
-- PROPOSED_finance_m3_payment_guards.sql
-- TaskOra Finance — Migration M3: DB-level overpayment prevention, concurrency,
--   void-aware status sync, audited payment + invoice-correction workflow, and
--   manager read-only RLS tightening (no internal-finance writes).
-- ----------------------------------------------------------------------------
-- Dependencies: M1 + M2 applied. Helpers is_global_admin(), is_manager(),
--   manager_client_ids() exist. Enums crm_entry_status, payment_method exist.
-- Access control (enforced at DB level):
--   * record/void payments and correct invoice amounts  → admin/super-admin only
--     (is_global_admin()), via SECURITY DEFINER RPCs.
--   * managers: SELECT on crm_entries/crm_payments for their team's clients,
--     plus INSERT of client-scoped crm_entries (preserves the calendar meeting-
--     cost → invoice path in client_repository). NO UPDATE/DELETE, NO payment
--     writes → no internal-finance mutation.
--   * employees: no crm_* policies → no access (unchanged).
--   * clients: SELECT own only (unchanged).
-- Overpayment: a BEFORE trigger on crm_payments rejects any active payment that
--   would push collected above the invoice amount — enforced for EVERY write
--   path, not just the RPC, and serialized via SELECT ... FOR UPDATE.
-- Invoice floor: a BEFORE trigger on crm_entries blocks amount < paid_amount and
--   requires amount changes to go through correct_crm_entry_amount() (audited).
-- Rollback: see ROLLBACK_finance.sql (M3 section).
-- ============================================================================

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- A) Void-aware status sync. Sums ONLY active payments; fires on I/U/D; locks
--    the parent invoice so concurrent payment writes serialize.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.sync_crm_payment_status()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_entry_id   uuid := coalesce(NEW.crm_entry_id, OLD.crm_entry_id);
  v_total_paid numeric(12,2);
  v_amount     numeric(12,2);
  v_new_status public.crm_entry_status;
begin
  -- Lock the parent invoice so concurrent payment writes serialize.
  select amount into v_amount from public.crm_entries where id = v_entry_id for update;

  select coalesce(sum(amount_paid), 0) into v_total_paid
    from public.crm_payments
   where crm_entry_id = v_entry_id and status = 'active';

  if    v_amount > 0 and v_total_paid >= v_amount then v_new_status := 'paid';
  elsif v_total_paid > 0                          then v_new_status := 'partial';
  else                                                 v_new_status := 'unpaid';
  end if;

  update public.crm_entries
     set paid_amount = v_total_paid,
         status  = case when status = 'cancelled' then 'cancelled' else v_new_status end,
         paid_at = case when v_new_status = 'paid' then now() else null end
   where id = v_entry_id;

  return null;  -- AFTER trigger
end;
$$;

drop trigger if exists crm_payment_status_sync on public.crm_payments;
create trigger crm_payment_status_sync
  after insert or update or delete on public.crm_payments
  for each row execute function public.sync_crm_payment_status();

-- ───────────────────────────────────────────────────────────────────────────
-- B) DB-level overpayment prevention (defense for ALL write paths).
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.guard_crm_payment_overpay()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_amount       numeric(12,2);
  v_active_total numeric(12,2);
begin
  -- Only active payments count toward the invoice; voids reduce, never overpay.
  if NEW.status <> 'active' then
    return NEW;
  end if;

  select amount into v_amount from public.crm_entries
    where id = NEW.crm_entry_id for update;
  if v_amount is null then
    raise exception 'CRM entry % not found', NEW.crm_entry_id
      using errcode = 'foreign_key_violation';
  end if;

  select coalesce(sum(amount_paid), 0) into v_active_total
    from public.crm_payments
   where crm_entry_id = NEW.crm_entry_id
     and status = 'active'
     and id <> NEW.id;             -- exclude self on UPDATE

  if v_active_total + NEW.amount_paid > v_amount then
    raise exception
      'Payment of % exceeds invoice outstanding (invoice total %, already collected %).',
      NEW.amount_paid, v_amount, v_active_total
      using errcode = 'check_violation';
  end if;

  return NEW;
end;
$$;

drop trigger if exists crm_payment_overpay_guard on public.crm_payments;
create trigger crm_payment_overpay_guard
  before insert or update on public.crm_payments
  for each row execute function public.guard_crm_payment_overpay();

-- ───────────────────────────────────────────────────────────────────────────
-- C) Invoice-amount floor + require audited correction workflow.
--    amount < paid_amount is ALWAYS rejected; any amount change must be made via
--    correct_crm_entry_amount() (which sets the transaction-local authorization).
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.guard_crm_entry_amount()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if NEW.amount is distinct from OLD.amount then
    if NEW.amount < NEW.paid_amount then
      raise exception
        'Invoice total (%) cannot be set below amount already collected (%). '
        'Void or refund payments first via the audited correction workflow.',
        NEW.amount, NEW.paid_amount
        using errcode = 'check_violation';
    end if;
    if coalesce(current_setting('app.crm_amount_correction', true), '') <> 'on' then
      raise exception
        'Invoice amount may only be changed via correct_crm_entry_amount().'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists crm_entry_amount_guard on public.crm_entries;
create trigger crm_entry_amount_guard
  before update on public.crm_entries
  for each row execute function public.guard_crm_entry_amount();

-- ───────────────────────────────────────────────────────────────────────────
-- D) Audited payment recording (admin/super-admin only).
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.record_crm_payment(
  p_crm_entry_id uuid,
  p_amount       numeric,
  p_payment_date date default current_date,
  p_method       public.payment_method_type default null,
  p_reference    text default null,
  p_notes        text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_client_id uuid;
  v_payment_id uuid;
begin
  if not public.is_global_admin() then
    raise exception 'Only an admin may record payments.' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be positive.' using errcode = 'check_violation';
  end if;

  select client_id into v_client_id from public.crm_entries
    where id = p_crm_entry_id for update;
  if not found then
    raise exception 'CRM entry % not found', p_crm_entry_id using errcode = 'no_data_found';
  end if;

  -- Overpay guard + status sync run via the crm_payments triggers.
  insert into public.crm_payments (
    crm_entry_id, client_id, amount_paid, payment_date,
    payment_method, reference_number, recorded_by, notes, status
  ) values (
    p_crm_entry_id, v_client_id, p_amount, coalesce(p_payment_date, current_date),
    p_method, p_reference, auth.uid(), p_notes, 'active'
  ) returning id into v_payment_id;

  insert into public.crm_payment_audit (payment_id, crm_entry_id, action, amount, actor_id, reason)
    values (v_payment_id, p_crm_entry_id, 'record', p_amount, auth.uid(), p_notes);

  return v_payment_id;
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- E) Audited payment void (admin/super-admin only). History is preserved.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.void_crm_payment(
  p_payment_id uuid,
  p_reason     text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_entry_id uuid;
  v_amount   numeric(12,2);
  v_status   text;
begin
  if not public.is_global_admin() then
    raise exception 'Only an admin may void payments.' using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'A reason is required to void a payment.' using errcode = 'check_violation';
  end if;

  select crm_entry_id, amount_paid, status into v_entry_id, v_amount, v_status
    from public.crm_payments where id = p_payment_id for update;
  if not found then
    raise exception 'Payment % not found', p_payment_id using errcode = 'no_data_found';
  end if;
  if v_status = 'voided' then
    raise exception 'Payment % is already voided.', p_payment_id using errcode = 'check_violation';
  end if;

  update public.crm_payments
     set status = 'voided', voided_by = auth.uid(), voided_at = now(), void_reason = p_reason
   where id = p_payment_id;  -- triggers re-sync paid_amount/status

  insert into public.crm_payment_audit (payment_id, crm_entry_id, action, amount, actor_id, reason)
    values (p_payment_id, v_entry_id, 'void', v_amount, auth.uid(), p_reason);
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- F) Audited invoice-amount correction (admin/super-admin only).
--    Floor = amount already collected. To go below, void/refund payments first
--    (also audited) — this is the "explicitly authorized, audited correction
--    workflow that handles the discrepancy safely".
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.correct_crm_entry_amount(
  p_crm_entry_id uuid,
  p_new_amount   numeric,
  p_reason       text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_old  numeric(12,2);
  v_paid numeric(12,2);
begin
  if not public.is_global_admin() then
    raise exception 'Only an admin may correct invoice amounts.' using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'A reason is required to correct an invoice amount.' using errcode = 'check_violation';
  end if;
  if p_new_amount is null or p_new_amount < 0 then
    raise exception 'Invoice amount must be zero or positive.' using errcode = 'check_violation';
  end if;

  select amount, paid_amount into v_old, v_paid
    from public.crm_entries where id = p_crm_entry_id for update;
  if not found then
    raise exception 'CRM entry % not found', p_crm_entry_id using errcode = 'no_data_found';
  end if;

  if p_new_amount < v_paid then
    raise exception
      'Cannot reduce invoice to % below the % already collected. '
      'Void/refund payments first (audited), then reduce the amount.',
      p_new_amount, v_paid
      using errcode = 'check_violation';
  end if;

  -- Authorize the guarded amount change for this statement only, then revert.
  perform set_config('app.crm_amount_correction', 'on', true);
  update public.crm_entries
     set amount   = p_new_amount,
         status   = (case
                      when status = 'cancelled' then 'cancelled'
                      when p_new_amount > 0 and paid_amount >= p_new_amount then 'paid'
                      when paid_amount > 0 then 'partial'
                      else 'unpaid' end)::public.crm_entry_status,
         paid_at  = case when p_new_amount > 0 and paid_amount >= p_new_amount
                         then coalesce(paid_at, now()) else null end
   where id = p_crm_entry_id;
  perform set_config('app.crm_amount_correction', 'off', true);

  insert into public.crm_entry_corrections
    (crm_entry_id, old_amount, new_amount, paid_amount_at_change, actor_id, reason)
  values
    (p_crm_entry_id, v_old, p_new_amount, v_paid, auth.uid(), p_reason);
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- G) Lock down executable surface (avoid new anon-callable DEFINER warnings).
-- ───────────────────────────────────────────────────────────────────────────
revoke all on function public.guard_crm_payment_overpay()  from public, anon, authenticated;
revoke all on function public.guard_crm_entry_amount()      from public, anon, authenticated;
revoke all on function public.sync_crm_payment_status()     from public, anon, authenticated;

revoke all on function public.record_crm_payment(uuid, numeric, date, public.payment_method_type, text, text) from public, anon;
grant  execute on function public.record_crm_payment(uuid, numeric, date, public.payment_method_type, text, text) to authenticated;

revoke all on function public.void_crm_payment(uuid, text) from public, anon;
grant  execute on function public.void_crm_payment(uuid, text) to authenticated;

revoke all on function public.correct_crm_entry_amount(uuid, numeric, text) from public, anon;
grant  execute on function public.correct_crm_entry_amount(uuid, numeric, text) to authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- H) Manager RLS: read-only finance (+ client-scoped invoice INSERT only).
--    Removes manager UPDATE/DELETE on invoices and ALL writes on payments.
-- ───────────────────────────────────────────────────────────────────────────
drop policy if exists "manager_team_crm_entries" on public.crm_entries;

create policy "manager_team_crm_entries_read" on public.crm_entries
  for select
  using (
    public.is_manager()
    and client_id in (select id from public.manager_client_ids())
  );

-- Preserves the calendar meeting-cost → client invoice path (client_repository).
create policy "manager_team_crm_entries_insert" on public.crm_entries
  for insert
  with check (
    public.is_manager()
    and client_id is not null
    and client_id in (select id from public.manager_client_ids())
  );

drop policy if exists "manager_team_crm_payments" on public.crm_payments;

create policy "manager_team_crm_payments_read" on public.crm_payments
  for select
  using (
    public.is_manager()
    and client_id in (select id from public.manager_client_ids())
  );

commit;
