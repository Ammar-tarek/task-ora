# Phase 1 — TimeTree-style Calendar investigation (read-only, nothing changed)

## A. Current architecture + department scoping
- **One shared calendar** — `lib/features/calendar/calendar_screen.dart`. Month / Week / Day views. Month grid is now **dense** (colored event bars in day cells, grid fills the screen, compact agenda below).
- **Data path**: staff → `ClientRepository.fetchDepartmentEvents(scopeTeamId)`; clients → `fetchClientEvents`. Scope = `WorkspaceScopeNotifier.taskScopeTeamId` (admin's active department; null = All Departments). The old in-calendar TEAM chips were removed — department comes from the **workspace header selector**.
- **RLS is the real boundary** (not UI): `events_department_manage` (manager, own team), `events_department_read` (employee, own team), `events_participant_read` (creator/attendee, staff), `Admin full`, `Client sees own visible`. Verified live.
- **`events` columns**: id, title, description, event_type (enum incl `room_booking`), start_time, end_time, location, is_recurring, recurrence_pattern, client_id, created_by, status, is_client_visible, meeting_notes, cost, shooting_hours, final_video_duration, **team_id**, **link**. `event_attendees` (dept-scoped) + `event_attachments` tables exist.
- **Reminders (do NOT touch)**: END (`send_event_reminders`, 60/5 before end) + START (`send_event_start_reminders`, configurable offsets) both live; EXECUTE grants locked down; delivery via `notifications` → `notifications_fcm_push` → FCM.

## B. Departments + roles supported
- **Teams**: Admins, Marketing, Montage, Sales, Studio, Video Production. The 5 calendar departments = **Marketing, Montage, Production (= Video Production), Sales, Studio** — all have teams.
- **Admins** = internal team, not a department workspace. **No Expenses team/calendar** — Expenses is company-wide by prior design. ⚠️ The prompt lists "Expenses" under calendar coverage; today it has no calendar. **Needs your decision** (keep excluded, or add an Expenses team — a data change).
- **Roles** (all via RLS, one shared calendar): admin → all depts, switches via header; manager → manage own dept; employee → read own dept + own/attended; client → own visible. Works today.

## C. TimeTree features — have vs missing
**Have:** shared calendar; month (dense) / week / day; department selector (workspace header); event bars in cells; today/selected indicators; month nav; create/edit (title, start/end **time**, client, description, **link/URL**, reminders); start + end reminders; per-event colors (derived); `event_attachments` backend.

**Missing (UI; some need backend):**
| Feature | Status |
|---|---|
| **Location** field in form | Column `location` EXISTS — just not shown. UI-only add. |
| **Attendees** in form | `event_attendees` + RLS exist; the form dropped the picker. UI-only re-add. |
| **Multi-day** events | `start_time`/`end_time` are timestamps; form only picks time (single day). Needs end-**date** picker + grid spanning. No migration. |
| **All-day** toggle | No `all_day` column → **migration needed**. |
| **Event color** picker | No `color` column → **migration needed**. |
| **To-do list** | No table → **migration needed**. |
| **File attachments** UI | Table exists; needs UI + Storage wiring. |
| **Repeat/recurrence** UI | Only `is_recurring`/`recurrence_pattern` flags; real recurrence = occurrence expansion (large). |
| "Create calendar" | = departments; reuse the selector, no new entity. |

## D. Files to change (Phase 2)
- `lib/features/calendar/calendar_screen.dart` — create/edit form (add Location; optionally attendees, end-date for multi-day); grid already dense.
- `lib/core/repositories/client_repository.dart` — `createEvent`/`updateEvent` to carry any new fields.
- (Only if approved) a propose-only migration for `all_day` / `color` / `event_todos`.

## E. Smallest safe plan
**No-migration slice (recommended first):**
1. Shared dense grid for all departments — already in place; confirm dept switching drives it.
2. Add the existing **Location** field to the form; keep Link/URL.
3. Re-add **Attendees** (reuse `event_attendees`, dept-scoped).
4. **Multi-day** via an end-date picker (existing timestamp columns) + grid span.

**Needs a propose-only migration (apply later with approval):** all-day toggle, event color, to-do list. Attachments UI needs Storage.

## F. Are DB changes required?
Only for **all-day, color, to-do**. Location, URL, attendees, multi-day, dense grid, and department switching all work on the **existing** schema.

## G. Risks
- Keep RLS as-is (events policies enforce isolation). Do not touch reminders/cron/FCM.
- Multi-day rendering in the dense grid adds layout complexity.
- "Expenses calendar" conflicts with the no-Expenses-team design → clarify before any data change.
- No device/screenshot here → visual match is by build + tests, not pixels.

**Recommendation:** approve the no-migration slice (location + attendees + multi-day on the shared dense grid); defer all-day/color/to-do/attachments to a separate approved migration. Awaiting your go-ahead before implementing.
