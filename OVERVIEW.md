# TaskOra (CashBack — Operations Dashboard) — Full Overview

> A deep-dive companion to the [README](./README.md): what this app **is**, the **idea** behind it, and **how it actually works** under the hood.

---

## 1. The Idea

**TaskOra** (internal product name "CashBack — Operations Dashboard") is an all-in-one **operations management app for small-to-medium businesses / agencies**. Instead of juggling separate tools for tasks, staff attendance, client billing, and reporting, a company runs the whole operation from one cross-platform app.

The core problem it solves: a small agency needs to

- assign and track work (tasks) across teams,
- know who actually showed up to the office and for how long,
- bill clients and watch the money,
- keep clients in the loop on their own tasks,
- and give the owner a single place to see how the business is doing.

TaskOra packages all of that into one Flutter app (Android, iOS, Web, Windows) backed by a Supabase cloud database, with **role-based access** so each kind of user only sees what they should.

**Signature feature:** attendance is **automatic** — employees are checked in/out simply by connecting to the company Wi-Fi, no manual clock-in required.

---

## 2. Who Uses It (Roles)

The whole app is organized around **5 roles**, each with a different view and permission set. Navigation is enforced automatically by the router — a user physically cannot reach a screen they aren't allowed to.

| Role | What they can do |
|---|---|
| **Super Admin** | Everything, plus system-level tools: full business report, archiving completed tasks, resetting the app. |
| **Admin** | Full day-to-day access: dashboard, tasks, finance, teams, users, roles, clients, analytics, settings. |
| **Manager** | Runs their own team: dashboard, tasks, calendar, finance (if their team is allowed), clients, attendance, expenses, penalties, and privilege editing scoped to their team. Cannot create/edit teams or see global analytics. |
| **Employee** | Tasks, calendar, automatic attendance, and their own penalty record. No finance, no user/team management. |
| **Client** | A self-service view: only their own tasks, calendar, and their own finance page. |

A newly signed-up employee who hasn't been added to a team yet lands on a **"pending approval"** screen and can't do anything until an admin/manager assigns them to a team.

---

## 3. Tech Stack

| Layer | Technology |
|---|---|
| UI framework | **Flutter 3.x** (Dart 3.x) — one codebase for Android, iOS, Web, Windows |
| Backend & DB | **Supabase** — hosted PostgreSQL + Auth + Realtime + Row-Level Security |
| State management | **Provider** (`ChangeNotifier`) |
| Navigation | **go_router** with an auth/role redirect guard |
| Charts | **fl_chart** |
| Auth hardening | **local_auth** (biometric lock) + **flutter_secure_storage** |
| Push notifications | **Firebase Cloud Messaging** (`firebase_messaging`) + `flutter_local_notifications` |
| Attendance | **connectivity_plus** + **network_info_plus** (Wi-Fi SSID detection) |
| Client messaging | **n8n** webhook → Telegram, via plain HTTP |
| PDF / reports | **pdf** + **printing** |
| Auto-update (Android) | **background_downloader** + **open_filex** + **package_info_plus** |

---

## 4. How the App Is Structured

```
lib/
├── main.dart                 # Entry point & app lifecycle wiring
├── firebase_options.dart     # Generated FCM config
├── core/                     # Everything shared across features
│   ├── auth/                 # AuthNotifier — central login state
│   ├── constants/            # app_roles
│   ├── models/               # Task, Team, Client, Profile, privileges…
│   ├── providers/            # Theme, locale, team filter, team privileges
│   ├── repositories/         # Data access layer (all Supabase queries)
│   ├── router/               # go_router + redirect guard (access control)
│   ├── services/             # Supabase, Wi-Fi attendance, n8n, notifications, APK update…
│   ├── theme/                # App theme & colors
│   ├── utils/                # Time, permissions, PDF export
│   └── widgets/              # Shared UI (bottom nav shell, tables, banners)
└── features/                 # One folder per screen/feature area
    ├── auth/ dashboard/ tasks/ calendar/ finance/ attendance/
    ├── penalties/ users/ roles/ teams/ clients/ expenses/
    ├── analytics/ notifications/ settings/ splash/ super_admin/
```

**Architecture pattern** — a clean 3-layer split:

1. **Screens (features/)** — pure UI, read data from…
2. **Repositories (core/repositories/)** — the only place that talks to Supabase; each returns typed models.
3. **Services (core/services/)** — cross-cutting background logic (auth stream, Wi-Fi tracking, push, webhooks) that doesn't belong to a single screen.

State flows through **Provider**: `AuthNotifier`, `ThemeController`, `LocaleController`, `TeamFilterNotifier`, and `TeamPrivilegesNotifier` are injected at the top of the widget tree in `main.dart`.

---

## 5. How It Works — Key Mechanisms

### 5.1 Startup & lifecycle (`main.dart`)
1. Initialize Supabase and locale formatting in parallel.
2. Start the **RealtimeService** so the app auto-refreshes when data changes server-side.
3. Build the **router once** (outside the widget tree) and hand it the `AuthNotifier`.
4. Boot local + push notifications in the background after the first frame.
5. On every login, start **Wi-Fi attendance**, **notification triggers**, **push registration**, and an **APK update check**; on logout, tear them down.
6. When the app returns to the foreground, it re-checks Wi-Fi attendance, checks for updates, and reloads team privileges so permission changes take effect.

### 5.2 Authentication (`AuthNotifier`)
- Listens to Supabase's auth stream (`signedIn`, `tokenRefreshed`, `signedOut`).
- On a stored session it **refreshes an expired token before** loading any data, so pages don't fail with RLS errors.
- Fetches the user's **profile** (which carries their role + team) and exposes convenient getters (`isAdmin`, `isManager`, `isEmployee`, `isClient`, `isSuperAdmin`).
- Supports an optional **biometric lock** (`AuthStatus.biometricRequired`) — the app sits on the splash screen until Face/fingerprint unlock.
- FCM token is only cleared on an **explicit logout**, never on transient states.

### 5.3 Navigation & access control (`app_router.dart`)
A single `redirect` function runs on every navigation **and** every time auth state changes (`refreshListenable: auth`). It enforces, in order:
1. Loading / biometric-lock → stay on splash.
2. Not logged in → force to `/login` (or signup/forgot-password).
3. Pending employee (no team) → lock to `/pending`.
4. Logged in on an auth screen → send to the role's home (`/dashboard` for admin/manager, `/tasks` for employee/client).
5. **Role guards** — clients, managers, and employees are redirected away from any route they're not allowed to open; super-admin routes are gated too.

The main shell uses a `StatefulShellRoute` with a bottom navigation bar (Dashboard · Tasks · Calendar · Finance · Settings), plus full-page routes for admin/management screens.

### 5.4 Automatic Wi-Fi attendance (`wifi_attendance_service.dart`)
This is the standout feature. A singleton service:
- Reads the **company Wi-Fi SSIDs** (multiple allowed) and the on/off toggle from a central `app_settings` table — admin-controlled, mirrored to local cache so it keeps working briefly offline.
- Subscribes to connectivity changes. When the device joins **any** configured company network, it **auto-checks the employee in** and starts a session timer.
- When the device leaves, it waits out a **25-second grace period** before checking out — this absorbs the blip when the OS hands off between two company networks, so a legitimate switch never clocks someone out.
- All handlers are **serialized with a lock** so rapid connectivity callbacks can't create duplicate check-ins/outs.
- On web (browsers can't read the SSID) it falls back to treating any Wi-Fi as the company network.
- Check-out records the **accumulated minutes** of the session via `AttendanceRepository`.

### 5.5 Tasks & the client-approval workflow
Tasks move through a status pipeline (seen in `n8n_service` and the task models):

```
not_started → in_progress → employee_done → client_approved / client_rejected → completed
                                                     ↘ on_hold
```

Employees do the work and mark it done; the **client** approves or rejects their own tasks; admins/managers oversee the board. Tasks have priority, due dates, completion %, assignees, comments, attachments, approvals, and an audit log (see the schema). Boards support **Kanban + table views** and custom status options.

### 5.6 Client notifications via n8n → Telegram (`n8n_service.dart`)
When an admin/manager saves a task that has a client attached, the app fires a **fire-and-forget HTTP POST** to an **n8n webhook** (URL set once in Settings) with the client's phone, task title, status, priority, due date, and completion %. n8n then messages the client on **Telegram**. The call is wrapped so a webhook failure can never block or crash the task save.

### 5.7 Notifications (in-app + push)
- **RealtimeService** + **NotificationTriggerService** watch Supabase in real time and raise in-app notifications.
- **PushNotificationService** registers the device with **Firebase Cloud Messaging** for background push.
- **LocalNotificationService** shows local notifications and can deep-link into the right screen via the router.

### 5.8 Finance, expenses, penalties, analytics
- **Finance** dashboard + analytics, with a per-client finance screen (clients see only their own). Backed by `crm_entries` / `crm_payments` tables.
- **Daily expenses** with categories.
- **Penalties** per employee (employees see only their own record).
- **Advanced analytics** and charts for admins; the **Super Admin report** can be exported to **PDF**.

### 5.9 Auto-update (Android)
`ApkUpdateService` checks an `app_versions` table on login/foreground; if a newer build exists it downloads the APK in the background and offers to install it — so field devices stay current without a store.

### 5.10 Theming & localization
- Light/dark theme via `ThemeController` (the active palette is applied globally).
- **English + Arabic** (RTL) support via `flutter_localizations` and a `LocaleController`.

---

## 6. The Database (Supabase / PostgreSQL)

The full schema lives in [`SupaBase.sql`](./SupaBase.sql). It uses **Row-Level Security** so the database itself enforces who can read/write what. Major table groups:

- **People & structure:** `teams`, `profiles`, `client_profiles`
- **Tasks:** `tasks`, `task_assignees`, `task_mentions`, `task_approvals`, `task_comments`, `task_attachments`, `task_audit_log`, `task_boards`, `task_board_columns`
- **Client visibility:** `client_task_visibility`, `client_task_column_visibility`
- **Scheduling:** `events`, `event_attendees`, `event_attachments`, `rooms`, `room_bookings`
- **Finance:** `crm_entries`, `crm_payments`, `expenses`, `expense_categories`
- **HR:** `attendance`, `penalties`, `penalty_types`
- **Flexible/custom tables:** `custom_tables`, `custom_columns`, `column_status_options`, `custom_rows`, `custom_cell_values`, `table_views`, `table_permissions`, `cell_audit_log`
- **Notes/knowledge:** `notes`, `note_tags`, `note_shares`, `note_attachments`, `note_links`, `note_audit_log`
- **System:** `notifications`, `ai_interactions`, `app_versions`

---

## 7. Data Flow at a Glance

```
┌────────────────────────────────────────────────────────────┐
│                     Flutter App (UI)                         │
│   features/*  ← Provider state (Auth, Theme, Locale, …)      │
└───────────────┬───────────────────────┬─────────────────────┘
                │                        │
        repositories/              services/ (background)
                │                   │        │        │
                ▼                   ▼        ▼        ▼
          ┌──────────┐        Wi-Fi     FCM push   n8n webhook
          │ Supabase │        attendance  ▲          │
          │ Postgres │◀───────────────────┘          ▼
          │ + Auth   │                           Telegram
          │ + RLS    │◀── Realtime subscriptions → in-app notifs
          └──────────┘
```

---

## 8. Running It (quick reference)

```bash
flutter pub get
flutter run              # device/emulator
flutter run -d chrome    # web
flutter run -d windows   # desktop
flutter build apk --release
```

Full setup instructions (Flutter SDK, Android Studio, licenses) are in the [README](./README.md).

---

## 9. Summary in One Line

> TaskOra is a Flutter + Supabase operations hub where a business runs tasks, auto-tracks attendance over Wi-Fi, bills and updates clients (via Telegram), and reports on the whole thing — with strict role-based access from the app router down to the database.
