-- ============================================================================
-- PROPOSED_finance_m1_schema_currency.sql
-- TaskOra Finance — Migration M1: department-owned manual revenue + EGP default
-- ----------------------------------------------------------------------------
-- Dependencies: public.crm_entries, public.teams (both exist).
-- Compatibility: crm_entries currently has 0 rows → currency backfill is a no-op
--   today but written idempotently for safety. Making client_id nullable is
--   backward compatible (all existing inserts still pass). Auto-CRM triggers
--   (task/room_booking) always set client_id, so they are unaffected.
-- RLS impact: none changed here. Rows with NULL client_id become admin-only
--   automatically (client/manager policies key on client_id), which is exactly
--   the "internal manual revenue = admin/super-admin only" requirement.
-- Rollback: see ROLLBACK_finance.sql (M1 section).
-- ============================================================================

begin;

-- 1) Department ownership for manual internal revenue (no client required).
alter table public.crm_entries
  add column if not exists team_id uuid references public.teams(id) on delete set null;

comment on column public.crm_entries.team_id is
  'Owning department for manual internal revenue rows. NULL for client-sourced '
  'entries (task/room_booking). Rows with NULL client_id are admin-only via RLS.';

-- 2) Allow client-less manual revenue, but always require an owner.
alter table public.crm_entries
  alter column client_id drop not null;

alter table public.crm_entries
  add constraint crm_entries_owner_ck
  check (client_id is not null or team_id is not null);

-- 3) EGP as the default currency; backfill legacy USD rows (currently none).
alter table public.crm_entries
  alter column currency set default 'EGP';

update public.crm_entries set currency = 'EGP' where currency = 'USD';

-- 4) Indexes supporting the department revenue sheet (owner FK + source filter).
create index if not exists idx_crm_entries_team_id    on public.crm_entries(team_id);
create index if not exists idx_crm_entries_source_type on public.crm_entries(source_type);

commit;
