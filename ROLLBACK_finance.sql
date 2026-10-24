-- ============================================================================
-- ROLLBACK_finance.sql — reverse M3 → M2 → M1 (run sections in this order).
-- NOTE: Roll back the app (git revert) BEFORE rolling back the database.
-- M1's client_id NOT NULL restore is only safe while no client-less manual
-- rows exist; the section guards against that and aborts if any are present.
-- ============================================================================

-- ── M3 rollback ─────────────────────────────────────────────────────────────
begin;

drop policy if exists "manager_team_crm_payments_read"  on public.crm_payments;
drop policy if exists "manager_team_crm_entries_insert" on public.crm_entries;
drop policy if exists "manager_team_crm_entries_read"   on public.crm_entries;

-- Restore original manager ALL policies.
create policy "manager_team_crm_entries" on public.crm_entries
  for all
  using      (public.is_manager() and client_id in (select id from public.manager_client_ids()))
  with check (public.is_manager() and client_id in (select id from public.manager_client_ids()));
create policy "manager_team_crm_payments" on public.crm_payments
  for all
  using      (public.is_manager() and client_id in (select id from public.manager_client_ids()))
  with check (public.is_manager() and client_id in (select id from public.manager_client_ids()));

drop function if exists public.correct_crm_entry_amount(uuid, numeric, text);
drop function if exists public.void_crm_payment(uuid, text);
drop function if exists public.record_crm_payment(uuid, numeric, date, public.payment_method, text, text);

drop trigger if exists crm_entry_amount_guard on public.crm_entries;
drop function if exists public.guard_crm_entry_amount();
drop trigger if exists crm_payment_overpay_guard on public.crm_payments;
drop function if exists public.guard_crm_payment_overpay();

-- Restore the original INSERT-only status sync.
create or replace function public.sync_crm_payment_status()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_total_paid DECIMAL(12,2);
  v_amount     DECIMAL(12,2);
  v_new_status public.crm_entry_status;
BEGIN
  SELECT COALESCE(SUM(amount_paid), 0) INTO v_total_paid
    FROM public.crm_payments WHERE crm_entry_id = NEW.crm_entry_id;
  SELECT amount INTO v_amount FROM public.crm_entries WHERE id = NEW.crm_entry_id;
  IF    v_total_paid >= v_amount THEN v_new_status := 'paid';
  ELSIF v_total_paid  > 0        THEN v_new_status := 'partial';
  ELSE                                v_new_status := 'unpaid';
  END IF;
  UPDATE public.crm_entries
     SET paid_amount = v_total_paid, status = v_new_status,
         paid_at = CASE WHEN v_new_status = 'paid' THEN NOW() ELSE NULL END
   WHERE id = NEW.crm_entry_id;
  RETURN NEW;
END;
$$;
drop trigger if exists crm_payment_status_sync on public.crm_payments;
create trigger crm_payment_status_sync
  after insert on public.crm_payments
  for each row execute function public.sync_crm_payment_status();

commit;

-- ── M2 rollback ─────────────────────────────────────────────────────────────
begin;
drop table if exists public.crm_entry_corrections;
drop table if exists public.crm_payment_audit;
drop index if exists public.idx_crm_payments_status;
-- client_id restore for payments (safe: voided columns dropped below).
-- Only restore NOT NULL if no NULL client_id payment rows exist.
do $$
begin
  if exists (select 1 from public.crm_payments where client_id is null) then
    raise exception 'crm_payments has NULL client_id rows; cannot restore NOT NULL';
  end if;
  alter table public.crm_payments alter column client_id set not null;
end $$;
alter table public.crm_payments drop column if exists void_reason;
alter table public.crm_payments drop column if exists voided_at;
alter table public.crm_payments drop column if exists voided_by;
alter table public.crm_payments drop column if exists status;
commit;

-- ── M1 rollback ─────────────────────────────────────────────────────────────
begin;
drop index if exists public.idx_crm_entries_source_type;
drop index if exists public.idx_crm_entries_team_id;
alter table public.crm_entries alter column currency set default 'USD';
alter table public.crm_entries drop constraint if exists crm_entries_owner_ck;
do $$
begin
  if exists (select 1 from public.crm_entries where client_id is null) then
    raise exception 'crm_entries has NULL client_id rows; cannot restore NOT NULL';
  end if;
  alter table public.crm_entries alter column client_id set not null;
end $$;
alter table public.crm_entries drop column if exists team_id;
commit;
