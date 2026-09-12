-- Attendance overnight-session fix (DB side).
--
-- Background: check-out used to locate the row by (employee_id, today). A
-- session that crossed Cairo midnight could not be closed on its own day, and
-- the WiFi auto-checkout could write a check_out_time onto an absent row that
-- had check_in_time IS NULL. The old constraint
--   CHECK (check_out_time IS NULL OR check_out_time > check_in_time)
-- let that through, because `check_out_time > NULL` evaluates to UNKNOWN, which
-- a CHECK constraint treats as satisfied.
--
-- The application now closes the employee's OPEN session (check_in set,
-- check_out NULL) by id instead of by date. This migration strengthens the
-- constraint so the corrupt state can never be stored again.

-- (1) Clean the corrupt rows produced by the old bug: a check_out_time with no
-- check_in_time is an impossible state. Null out the stray checkout and its
-- garbage hours; the row itself (e.g. an approved 'absent' day) is preserved.
UPDATE public.attendance
SET check_out_time = NULL,
    total_hours    = NULL
WHERE check_in_time IS NULL
  AND check_out_time IS NOT NULL;

-- (2) Strengthen the constraint: a non-null check_out_time now REQUIRES a
-- non-null check_in_time and must still be strictly after it. Open sessions
-- (check_in set, check_out NULL) and time-less rows (both NULL) remain valid.
ALTER TABLE public.attendance
  DROP CONSTRAINT IF EXISTS att_checkout_after_checkin;

ALTER TABLE public.attendance
  ADD CONSTRAINT att_checkout_after_checkin
  CHECK (
    check_out_time IS NULL
    OR (check_in_time IS NOT NULL AND check_out_time > check_in_time)
  );
