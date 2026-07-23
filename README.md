<h1 align="center">CB TO-DO — Operations Dashboard</h1>

<p align="center">
  A cross-platform Flutter application for managing teams, tasks, attendance, finance, and clients — built for CSE Graduation Project Group 23.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-blue?logo=dart" />
  <img src="https://img.shields.io/badge/Backend-Supabase-green?logo=supabase" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" />
</p>

---

## Table of Contents

- [About the Project](#about-the-project)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the App](#running-the-app)
- [Building a Release APK](#building-a-release-apk)
- [Project Structure](#project-structure)
- [Role-Based Access](#role-based-access)
- [Team](#team)

---

## About the Project

**TaskOra** is a full-featured operations management dashboard designed for small-to-medium businesses. It allows admins and managers to oversee tasks, track employee attendance via Wi-Fi, manage finances, handle client accounts, and analyze performance — all from a single mobile/web app.

The app connects to a **Supabase** backend (PostgreSQL + Auth + Realtime) and supports four user roles with different levels of access.

---

## Features

| Module | Description |
|---|---|
| **Authentication** | Login, Sign Up, Forgot Password with Supabase Auth |
| **Dashboard** | Admin overview with KPIs and quick stats |
| **Task Management** | Kanban board + table view, task detail, custom status options |
| **Calendar** | Monthly calendar with task deadlines and events |
| **Finance** | Finance dashboard, analytics, per-client finance view |
| **Attendance** | Automatic Wi-Fi-based check-in/check-out for employees |
| **Penalties** | Penalty records per employee, visible to admins and employees |
| **Users & Roles** | Create users, assign roles, edit permissions |
| **Team Management** | Create teams, assign members, view team members |
| **Clients** | Client list with individual finance screens |
| **Expenses** | Daily expense tracking |
| **Analytics** | Advanced analytics and charts |
| **Notifications** | In-app notification center |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **UI Framework** | [Flutter](https://flutter.dev) 3.x |
| **Language** | Dart 3.x |
| **Backend & Database** | [Supabase](https://supabase.com) (PostgreSQL + Auth + RLS) |
| **State Management** | [Provider](https://pub.dev/packages/provider) |
| **Navigation** | [go_router](https://pub.dev/packages/go_router) |
| **Charts** | [fl_chart](https://pub.dev/packages/fl_chart) |
| **Fonts** | [Google Fonts](https://pub.dev/packages/google_fonts) |
| **Connectivity** | connectivity_plus, network_info_plus |
| **Automation** | n8n webhooks via HTTP |

---

## Prerequisites

Before you can run this project, make sure you have the following installed on your computer:

### 1. Flutter SDK
- Download from: https://docs.flutter.dev/get-started/install
- Choose your operating system (Windows / macOS / Linux)
- Follow the installation guide and add Flutter to your system PATH
- Minimum required version: **Flutter 3.x / Dart 3.x**

Verify installation:
```bash
flutter --version
```

### 2. Git
- Download from: https://git-scm.com/downloads
- Used to clone the repository

### 3. Android Studio (for Android builds)
- Download from: https://developer.android.com/studio
- During first launch, complete the setup wizard — it installs the Android SDK automatically
- Inside Android Studio: go to **Tools → SDK Manager → SDK Tools** and check **Android SDK Command-line Tools (latest)**

### 4. VS Code (optional but recommended)
- Download from: https://code.visualstudio.com
- Install the **Flutter** and **Dart** extensions

---

## Installation

Follow these steps on **any computer** (Windows, macOS, or Linux):

### Step 1 — Clone the repository

```bash
git clone https://github.com/CSE-Graduation-Projects/GP-Group-23.git
cd GP-Group-23
```

### Step 2 — Install Flutter dependencies

```bash
flutter pub get
```

### Step 3 — Verify your environment

```bash
flutter doctor
```

All required items should show a green checkmark. Fix any issues it reports before continuing.

### Step 4 — Accept Android licenses (first time only)

```bash
flutter doctor --android-licenses
```

Press `y` to accept each license when prompted.

---

## Running the App

### On an Android device or emulator

1. Connect your Android device via USB and enable **USB Debugging** in developer options, OR launch an Android emulator from Android Studio
2. Run:
```bash
flutter run
```

### On a Web browser

```bash
flutter run -d chrome
```

### On Windows desktop

```bash
flutter run -d windows
```

### On a specific device (if multiple are connected)

```bash
flutter devices          # list all connected devices
flutter run -d <device-id>
```

---

## Building a Release APK

To build a signed release APK for Android:

```bash
flutter build apk --release
```

The output file will be located at:
```
build/app/outputs/flutter-apk/app-release.apk
```

You can transfer this file to any Android phone and install it directly.

> **Note:** If you get an error about missing Android SDK, make sure Android Studio is installed and `flutter doctor --android-licenses` has been run successfully.

---

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── core/
│   ├── auth/                          # Authentication state (AuthNotifier)
│   ├── models/                        # Data models (Task, Team, Client, etc.)
│   ├── repositories/                  # Data access layer (Supabase queries)
│   ├── router/                        # App navigation (go_router)
│   ├── services/                      # Supabase, WiFi attendance, n8n
│   ├── theme/                         # App theme and colors
│   ├── utils/                         # Helpers and permission utilities
│   └── widgets/                       # Shared widgets (BottomNav, tables)
└── features/
    ├── auth/                          # Login, Signup, Forgot Password screens
    ├── dashboard/                     # Admin dashboard
    ├── tasks/                         # Task board, table, detail screens
    ├── calendar/                      # Calendar screen
    ├── finance/                       # Finance dashboard and analytics
    ├── attendance/                    # Attendance tracking screen
    ├── penalties/                     # Penalty management
    ├── users/                         # User management
    ├── roles/                         # Roles editor
    ├── teams/                         # Team management and members
    ├── clients/                       # Client list and client finance
    ├── expenses/                      # Daily expenses
    ├── analytics/                     # Advanced analytics
    ├── notifications/                 # Notifications center
    ├── settings/                      # App settings
    └── splash/                        # Splash screen
```

---

## Role-Based Access

The app supports **4 user roles**, each with different permissions:

| Role | Access |
|---|---|
| **Admin** | Full access to all features |
| **Manager** | Dashboard, tasks, calendar, finance, teams, clients, analytics |
| **Employee** | Tasks, calendar, attendance, their own penalties |
| **Client** | Their own tasks, calendar, and their own finance page |

Navigation and routes are automatically restricted based on the logged-in user's role.

---

## Database

The database schema is documented in [`SupaBase.sql`](./SupaBase.sql).

The app uses **Supabase** as its backend:
- PostgreSQL database with Row Level Security (RLS)
- Supabase Auth for user management
- Realtime subscriptions for live updates

---

## Team

**CSE Graduation Project — Group 23**

> Faculty of Computer Science and Engineering

---

<p align="center">Built with Flutter & Supabase</p>
