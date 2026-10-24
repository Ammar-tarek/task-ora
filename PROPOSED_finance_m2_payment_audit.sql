-- ============================================================================
-- PROPOSED_finance_m2_payment_audit.sql
-- TaskOra Finance — Migration M2: payment void state + durable audit trails
-- ----------------------------------------------------------------------------
-- Dependencies: M1 applied (crm_entries owner model). crm_payments, profiles.
-- Compatibility: additive only. New crm_payments.status defaults to 'active',
--   so existing/auto behavior is unchanged. crm_payments.client_id made nullable
--   so payments can attach to client-less internal invoices (M1).
-- Audit tables are append-only: RLS enabled, SELECT for admin only, and NO
--   insert/update/delete policies — writes come solely from the SECURITY DEFINER
--   functions in M3 (which run as owner and bypass RLS). This matches the
--   existing task_audit_log / cell_audit_log immutability pattern.
-- Rollback: see ROLLBACK_finance.sql (M2 section).
-- ============================================================================

begin;

-- 1) Void / correction state on individual payments (history is never deleted).
alter table public.crm_payments
  add column if not exists status text not null default 'active'
    check (status in ('active','voided'));
alter table public.crm_payments
  add column if not exists voided_by uuid references public.profiles(id) on delete set null;
alter table public.crm_payments
  add column if not exists voided_at timestamptz;
alter table public.crm_payments
  add column if not exists void_reason text;

-- Payments can attach to a client-less internal invoice (M1 owner model).
alter table public.crm_payments
  alter column client_id drop not null;

create index if not exists idx_crm_payments_status on public.crm_payments(status);

-- 2) Durable, append-only payment audit trail (record / void).
create table if not exists public.crm_payment_audit (
  id           uuid primary key default gen_random_uuid(),
  payment_id   uuid not null references public.crm_payments(id) on delete restrict,
  crm_entry_id uuid not null references public.crm_entries(id)  on delete restrict,
  action       text not null check (action in ('record','void')),
  amount       numeric(12,2) not null,
  actor_id     uuid references public.profiles(id) on delete set null,
  reason       text,
  created_at   timestamptz not null default now()
);
comment on table public.crm_payment_audit is
  'Append-only log of payment record/void actions. No UPDATE/DELETE policies — immutable by design.';

alter table public.crm_payment_audit enable row level security;
drop policy if exists "Admin reads crm_payment_audit" on public.crm_payment_audit;
create policy "Admin reads crm_payment_audit" on public.crm_payment_audit
  for select using (public.is_global_admin());

-- 3) Durable, append-only invoice-amount correction trail.
create table if not exists public.crm_entry_corrections (
  id                    uuid primary key default gen_random_uuid(),
  crm_entry_id          uuid not null references public.crm_entries(id) on delete restrict,
  old_amount            numeric(12,2) not null,
  new_amount            numeric(12,2) not null,
  paid_amount_at_change numeric(12,2) not null,
  actor_id              uuid references public.profiles(id) on delete set null,
  reason                text not null,
  created_at            timestamptz not null default now()
);
comment on table public.crm_entry_corrections is
  'Append-only log of invoice/revenue amount corrections. No UPDATE/DELETE policies — immutable.';

alter table public.crm_entry_corrections enable row level security;
drop policy if exists "Admin reads crm_entry_corrections" on public.crm_entry_corrections;
create policy "Admin reads crm_entry_corrections" on public.crm_entry_corrections
  for select using (public.is_global_admin());

commit;
