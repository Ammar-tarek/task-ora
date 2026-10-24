# Finance Reset — Review & Impact Analysis

**Prepared:** 2026-10-24 · **Status:** preparation only — nothing executed, applied, committed, or deployed.
**Target DB:** production Supabase (project in `E:\task-ora`).

## 1. Approved scope
Wipe **all rows** from these 5 tables only:
`crm_payment_audit`, `crm_entry_corrections`, `crm_payments`, `crm_entries`, `expenses`.

Keep (untouched): `penalties`, `expense_categories`, `penalty_types`, and every other table and DB object.
`expenses` is shared with Department Finance — its rows are cleared by approval; Department Finance **code/config is not changed**.

## 2. Live row counts (captured 2026-10-24)
| Table | Rows |
|---|---|
| crm_payment_audit | 2 |
| crm_entry_corrections | 0 |
| crm_payments | 2 |
| crm_entries | 3 (all `source_type = manual`) |
| expenses | 5 |
| **Total** | **12** |

Excluded, preserved: penalties = 2, expense_categories = 10, penalty_types = 4.

## 3. Foreign-key / dependency map (verified live)
Inbound FKs to the target tables come **only from within the set**:
- `crm_payments.crm_entry_id → crm_entries` (ON DELETE RESTRICT)
- `crm_payment_audit.crm_entry_id → crm_entries` (RESTRICT)
- `crm_payment_audit.payment_id → crm_payments` (RESTRICT)
- `crm_entry_corrections.crm_entry_id → crm_entries` (RESTRICT)

Outbound FKs (target → others) are RESTRICT / SET NULL and are **not** affected by deleting the child rows:
- `crm_entries → client_profiles / profiles / teams`
- `crm_payments → crm_entries / client_profiles / profiles`
- `expenses → expense_categories / profiles`

**No table outside the set references any target table.** So: no external RESTRICT blocks the delete, and no cascade can escape the approved scope. Nothing in tasks, bookings, clients, attendance, departments, users, or profiles is touched.

### CRM origin check
All 3 `crm_entries` are `source_type = manual` (no task- or booking-generated rows present). Triggers `task_approved_crm` (tasks) and `room_booking_crm` (room_bookings) only **create** CRM rows going forward; they do not read deleted history, so clearing CRM does not break tasks or bookings.

## 4. Trigger side-effects during deletion (verified)
- Deleting `crm_payments` fires `sync_crm_payment_status` → it **UPDATEs the parent `crm_entries` paid_amount/status only** (not `amount`). `guard_crm_entry_amount` raises only when `amount` changes, so it does **not** block the delete.
- `guard_crm_payment_overpay` is INSERT/UPDATE-only → irrelevant to deletes.
- `expenses` deletes fire no triggers (`trg_notify_expense_approved` is UPDATE-only).
- `crm_payment_audit`, `crm_entry_corrections` have no triggers.

## 5. Deletion order (child → parent)
1. `crm_payment_audit`
2. `crm_entry_corrections`
3. `crm_payments`
4. `crm_entries`
5. `expenses`

Script: `PREPARED_finance_reset.sql` — one transaction, `DELETE` (not TRUNCATE), with **preconditions** (abort if counts drifted from 2/0/2/3/5 or an orphan payment appears) and **postconditions** (all 5 empty; penalties/config still 2/10/4). No `DROP`, no schema change.

## 6. Backup & restore
- **Backup:** `BACKUP_finance_2026-10-24.sql` — full row snapshot (every column, PKs, timestamps) as JSON. Method: `SELECT json_agg(to_jsonb(t))` per table via read-only SELECT.
- **Restore:** `RESTORE_finance_backup.sql` — `json_populate_recordset` inserts, parent→child, `ON CONFLICT (id) DO NOTHING`.
- **Location:** session scratchpad (local, access-controlled, **not** in git — holds real financial data):
  `C:\Users\yousi\AppData\Local\Temp\claude\E--task-ora\1410f169-e545-45c8-b44f-c89ed02f229d\scratchpad\`
- **Verification:** backup row counts equal live counts (12 rows: 2/0/2/3/5). JSON captured directly from the same SELECT used for counts, so content matches.
- **Restore caveat:** re-inserting payments re-runs `sync_crm_payment_status`; `paid_at` is re-stamped to `now()` for fully-paid entries (cosmetic; collected amounts unchanged).

## 7. Rollback strategy
Reset is a hard `DELETE`; the only undo is `RESTORE_finance_backup.sql`. Prerequisite before running the reset: confirm the backup file exists and its counts match. Run restore as a privileged/service session (bypasses RLS).

## 8. Company Ledger migration (`PROPOSED_company_ledger.sql`) — fixes confirmed
- `ON CONFLICT (client_token) WHERE client_token IS NOT NULL DO NOTHING` on **both** RPC inserts (partial-index predicate now matches). **Proven** on a throwaway temp table: duplicate token → no-op, null token → inserts, no `42P10`.
- `company_record_expense` checks idempotency **inside** the advisory lock.
- Balance error message uses valid `RAISE EXCEPTION '... (%) ... (%)'` (no `%.2f`).
- **Extra hardening added this pass:** `company_cash_balance()` is now admin-gated (non-admins get NULL) and `EXECUTE` revoked from public/anon/authenticated (only the two owner RPCs call it). Prevents a logged-in non-admin from reading the company cash total.
- Ledger stays isolated: own `company_ledger` table, admin-only RLS; the shared `expenses` table is NOT repurposed.

## 9. Unresolved risks / assumptions
- Counts are a point-in-time snapshot (2026-10-24). The reset's precondition block re-checks them and aborts on drift — but re-run the live count just before executing.
- Restore must run with sufficient privilege (service role / admin) or RLS will block the inserts.
- `company_ledger` migration is still **not applied**; the new Company Expenses page stays empty until it is (separate approval).

## 10. Execution prerequisites (when approved)
1. Confirm `BACKUP_finance_2026-10-24.sql` present + counts verified.
2. Apply `PROPOSED_company_ledger.sql` (enum/table/RPCs) — separate approval.
3. Run `PREPARED_finance_reset.sql` in a transaction; review the NOTICE; COMMIT.
4. Report actual before/after counts.
