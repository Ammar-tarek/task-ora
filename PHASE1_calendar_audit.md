# Phase 1 — Calendar & Reminders Audit (read-only, nothing changed)

Project `csncaoqvercxvbfbzbfa`. No files edited, no SQL run that changes data.

## 1. Current architecture — what exists & is reusable
**Calendar UI** (`lib/features/calendar/calendar_screen.dart`)
- Month / Week / Day views. Department-scoped fetch via `events.team_id` + RLS; `WorkspaceScopeNotifier` drives the active department (old TEAM chips removed). Create + Edit event sheets: department derived from workspace (no picker), attendees scoped to the department team.

**`events` table**: `title, description, event_type` (enum: internal_meeting, client_meeting, deadline, room_booking, holiday, other), `start_time`/`end_time` (timestamptz), `location`, `is_recurring`, `recurrence_pattern`, `client_id`, `created_by`, `status`, `is_client_visible`, `meeting_notes`, `cost`, `shooting_hours`, `final_video_duration`, `team_id`.
- `event_attendees` (dept-scoped), `event_attachments` (exists, reusable for Files).

**Reminders (existing = END-time only)**
- `event_reminders(event_id, profile_id, offset_minutes, sent_at, created_at)`, UNIQUE(event_id,profile_id,offset_minutes). `CHECK offset_minutes IN (5, 60)`.
- `send_event_reminders()` (SECURITY DEFINER), cron `event-reminders-5min` runs **every minute** (`* * * * *`). Fires at **60 and 5 minutes before `end_time`**, fans out to the event's department recipients, dedups via the UNIQUE row, inserts a `meeting_reminder` notification. Cleanup cron daily 03:30.
- `notify_event_created` → `calendar_event` notification to department on create.

**Push delivery**
- `notifications` has trigger `notifications_fcm_push` → FCM (Edge Fn `send-fcm-notification`). `profiles.fcm_token` set for 9 users. So in-app + FCM push exist for the notification pipeline.

**"Calendars"** = departments (`team_id`). **No `calendars` table.**

## 2. Missing vs the TimeTree screenshots
- Multiple **named** calendars + "Create calendar" (TaskOra has departments only, no create-calendar UI).
- Dense **month grid with in-cell event bars** (screenshot 7). Current month view is lighter than that.
- Event editor fields NOT present: **all-day toggle, color/category, URL, to-do checklist, configurable START reminders, multiple reminders per event, repeat/recurrence UI**. Present: title, start/end, attendees, location, notes (`meeting_notes`), attachments, cost/shooting/final-video.
- **Start-time** reminders with user offsets (at time / 5 / 10 / 15 / 30 / 60 min / 1 day). Today reminders are **end-time, fixed 60/5, department-wide**, not per-user/per-event configurable.

## 3. DB changes that would be needed (PROPOSE only — not for this phase)
- `events`: `all_day boolean default false`, `color text`, `url text`. (Additive.)
- **Start reminders**: a config table `event_reminder_prefs(event_id, offset_minutes, [scope])` + relax the `offset_minutes` set (or a dedicated `kind` = start/end) + a new `send_event_start_reminders()` function reusing the existing minute cron, with its own dedup rows. **Keep the end-time system untouched** (separate kind/table).
- To-do checklist: `event_todos(event_id, text, done, position)`. Files: reuse `event_attachments`.
- Calendars: **reuse departments** — do NOT add a calendars table unless you truly want named sub-calendars; that would duplicate the department concept.
- Recurrence: `recurrence_pattern` exists but there is no occurrence expansion; real recurring reminders need per-occurrence logic (large).

## 4. How reminders work + platforms
- Delivery = cron → `notifications` insert → `notifications_fcm_push` → FCM. **Android/iOS push works** if FCM credentials are configured and tokens valid (9 tokens present).
- **Web push is NOT verified** — no confirmed service worker / VAPID setup. I will not claim web push works.

## 5. Do reliable start-reminders need schema / new scheduling?
**Yes.** Start reminders need (a) a config store, (b) a start-based send function, (c) the existing minute cron (reusable), (d) recompute-on-edit + cancel-on-delete, (e) dedup. All of that is a **migration** — propose-only, not applied here.

## 6. Risks
- Altering `event_reminders` semantics/`CHECK` could break the live end-time reminders → add a **separate** kind/table instead.
- Recurrence + per-occurrence reminders is a large, error-prone area → recommend defer or minimal single-occurrence support.
- Web push claims without real setup would be false → treat as not-working until verified.
- A pending item from the previous task: a DB guard blocking cross-department attendees (`PROPOSED_event_attendee_department_guard.sql`) is **proposed, not applied**.
- Don't weaken RLS; don't use service-role for user reads/writes.

## Recommendation
This is a very large, multi-phase build. Smallest safe first slice (local code + propose migrations, nothing applied):
1. Event editor polish: add all-day, color, URL, notes (reuse `meeting_notes`), to-do — UI + model + repo; propose the additive `events` columns + `event_todos`.
2. Configurable **start** reminders: UI offsets + propose `event_reminder_prefs` + `send_event_start_reminders` (reuse cron), separate from end-reminders.
3. Dense month grid with in-cell event bars.
Defer: recurrence expansion, named calendars (reuse departments), web push (needs infra).
