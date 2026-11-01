# Graph Report - task-ora  (2026-11-01)

## Corpus Check
- 352 files · ~219,778 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 62 file(s) not represented in the graph (top: (none) 11, .xml 10, .xcconfig 8)

## Summary
- 4001 nodes · 5440 edges · 256 communities (164 shown, 92 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 32 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ff7e977e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Calendar & Attendees
- Super Admin Reports
- Task Board & Filters
- Task Detail & Assignment
- Theme & Design System
- Finance Repository
- Clients Directory
- User Management
- Edge Functions & Service-Role Security
- Task Model
- Task Repository
- Create User Flow
- ../models/profile_model.dart
- Company Cash Ledger
- Super Admin Report PDF
- Client Finance
- Client Repository & Reminders
- Dashboard
- Notion Table Widget
- notifications_screen.dart
- Penalties Management
- Shared UI Widgets
- Router & Routes
- Department Revenue Sheet
- DB Schema: notify/teams
- Workspace Scope
- Team Members
- Team Performance
- WorkspaceScopeNotifier
- Local Notifications
- Penalty Repository
- Finance Migrations M1-M3
- Auth Session Notifier
- advanced_analytics_screen.dart
- Team Privileges
- task table screen
- public.events
- main
- login screen
- settings screen
- roles editor screen
- public.tasks
- user privileges screen
- biometric service
- mock data
- archive completed tasks dialog
- team screen
- company ledger repository
- expense repository
- team management screen
- notification repository
- dependencies
- profile model
- employee performance screen
- revenue department isolation test
- PUBLIC
- status options manager sheet
- team privileges notifier
- task status options repository
- profile repository
- AuthNotifier
- signup screen
- team_privileges_model.dart
- splash_screen.dart
- task permissions
- push notification service
- department workspace screen
- app settings repository
- team repository
- package:task_ora/core/models/profile_model.dart
- public.client_task_visibility
- client model
- package:flutter_test/flutter_test.dart
- index
- windows/flutter/generated_plugin_registrant.cc
- apk update service
- ../../core/models/profile_model.dart
- user privileges model
- dashboard repository
- supabase service
- start reminder offsets
- client_detail_screen.dart
- task model
- realtime service
- privileged ops
- supabase service
- task_month_visibility_test.dart
- department_gate_test.dart
- analytics repository
- static const String
- montage_monthly_progress_test.dart
- workspace_routing.dart
- notification trigger service
- team model
- List
- static const
- public.notifications
- monthly_revenue_screen.dart
- super admin pdf exporter
- flutter launcher icons
- _
- employee_status_workflow.dart
- app roles
- departments
- String?
- pubspec.yaml
- dark premium
- apk download banner
- archived_tasks_screen.dart
- core/auth/auth_notifier.dart
- sales_sheet_screen.dart
- my_application.cc
- department service
- currency
- calendar attendee scope
- task_status_option.dart
- PROPOSED company ledger
- analysis options.yaml
- monthly_revenue.dart
- index
- notification route
- load token
- department_gate.dart
- employee status workflow test
- package:flutter/foundation.dart
- dev dependencies
- compilerOptions
- reset app repository
- static const String
- package.json
- with
- Task Handoff — Direct Transfer (Option A): Security Review & Test Matrix
- widget_test.dart
- web notification stub
- with
- Changelog
- client_history.dart
- win32_window.cpp
- with
- BookingConflictException
- AppScrollBehavior
- task_handoff_lock_test.dart
- _gate_sql_guards.mjs
- GATES — Production department: Calendar-only workspace
- sales_sheet_entry.dart
- n8n_service.dart
- ../../core/models/client_model.dart
- client_history_test.dart
- bool get
- .mcp.json
- Task Status Pipeline & Client Approval
- flutter
- flutter localizations
- Supabase
- FlutterWindow
- Changelog
- Writing Guidelines for Postgres References
- GeneratedPluginRegistrant.swift
- win32_window.cpp
- utils.cpp
- manifest.json
- State
- Section Definitions
- _TaskBoardScreenState
- _ClientsScreenState
- bottom_nav_shell.dart
- task_handoff_lock.dart
- tavatar_test.dart
- revenue_monthly_test.dart
- AppDelegate
- ios/RunnerTests/RunnerTests.swift
- ClientDetailScreen
- FlutterMacOS
- team_performance_test.dart
- Supabase Postgres Best Practices
- AppDelegate
- GATES — Task Handoff: Direct Transfer (Option A)
- client_search_test.dart
- _CreateTaskSheetState
- RegisterGeneratedPlugins
- MainActivity.kt
- RunnerTests
- _CreateClientSheet
- advanced-full-text-search.md
- advanced-jsonb-indexing.md
- conn-idle-timeout.md
- conn-limits.md
- conn-pooling.md
- conn-prepared-statements.md
- data-batch-inserts.md
- data-n-plus-one.md
- data-pagination.md
- data-upsert.md
- lock-advisory.md
- lock-deadlock-prevention.md
- lock-short-transactions.md
- lock-skip-locked.md
- monitor-explain-analyze.md
- monitor-pg-stat-statements.md
- monitor-vacuum-analyze.md
- query-composite-indexes.md
- query-covering-indexes.md
- query-index-types.md
- query-missing-indexes.md
- query-partial-indexes.md
- schema-constraints.md
- schema-data-types.md
- schema-foreign-key-indexes.md
- schema-lowercase-identifiers.md
- schema-partitioning.md
- schema-primary-keys.md
- security-privileges.md
- security-rls-basics.md
- security-rls-performance.md
- _template.md
- README.md
- Size
- _EditClientSheet
- firebase-messaging-sw.js
- sales_sheet_repository.dart
- task_audit_insert_test.dart
- PROPOSED_task_status_options.sql
- PROPOSED_sales_sheet_entries.sql
- _AdminDashboardScreenState
- _EditEmployeeSheetState
- _UserCardState
- build
- WindowClassRegistrar::GetWindowClass

## God Nodes (most connected - your core abstractions)
1. `AuthNotifier` - 124 edges
2. `public.profiles` - 66 edges
3. `WorkspaceScopeNotifier` - 54 edges
4. `dependencies` - 25 edges
5. `TeamFilterNotifier` - 23 edges
6. `LocaleController` - 23 edges
7. `public.tasks` - 23 edges
8. `Win32Window` - 21 edges
9. `public.events` - 17 edges
10. `public.crm_entries` - 16 edges

## Surprising Connections (you probably didn't know these)
- `public.event_recipient_ids()` --reads_from--> `public.profiles`  [EXTRACTED]
  supabase/migrations/20261026_event_end_time_reminders_v2.sql → SupaBase.sql
- `public.send_event_reminders()` --reads_from--> `public.events`  [EXTRACTED]
  supabase/migrations/20261026_event_end_time_reminders_v2.sql → SupaBase.sql
- `task_ora desktop binary (BINARY_NAME)` --conceptually_related_to--> `TaskOra (CashBack Operations Dashboard)`  [INFERRED]
  windows/CMakeLists.txt → README.md
- `public.mark_daily_absentees()` --reads_from--> `public.profiles`  [EXTRACTED]
  supabase/migrations/20260909_attendance_late_and_absent_defaults.sql → SupaBase.sql
- `public.send_manual_attendance_reminders()` --reads_from--> `public.profiles`  [EXTRACTED]
  supabase/migrations/20260909_attendance_manual_reminder.sql → SupaBase.sql

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Calendar event reminder & push pipeline** — phase1_timetree_calendar_report_events_table, phase1_calendar_audit_event_reminders, phase1_calendar_audit_notifications_fcm_push, overview_fcm_push [EXTRACTED 0.85]
- **Service-role key removal & replacement flow** — isolation_final_report_service_role_key, blockers_service_role_removal_admin_user_ops, blockers_service_role_removal_admin_reset_app, backend_security_plan_key_rotation, department_isolation_audit_b2_service_role_reads [EXTRACTED 0.90]
- **DB-level department isolation enforcement** — department_isolation_audit_rls, department_migration_assessment_security_definer_helpers, department_migration_assessment_guard_trigger, department_migration_assessment_teams_as_departments, department_isolation_audit_workspace_scope_notifier [INFERRED 0.80]

## Communities (256 total, 92 thin omitted)

### Community 0 - "Calendar & Attendees"
Cohesion: 0.02
Nodes (127): _addRoom, assigneeInitials, attendeeIds, attendeeNames, build, _buildAppBar, _buildBody, _buildFab (+119 more)

### Community 1 - "Super Admin Reports"
Cohesion: 0.02
Nodes (126): absentCount, add, amount, assignedTasks, assignees, attachmentUrl, attendanceList, attendanceLogs (+118 more)

### Community 2 - "Task Board & Filters"
Cohesion: 0.02
Nodes (115): active, activeColor, _activeMonth, _addMonths, _allEmployees, _archiveSelectedTasks, _archiveTaskRow, _assigneeId (+107 more)

### Community 3 - "Task Detail & Assignment"
Cohesion: 0.02
Nodes (92): _acceptAssignment, _allEmployees, _approve, _archiving, _assignmentBanner, _assignmentOnly, _banner, _buildActions (+84 more)

### Community 4 - "Theme & Design System"
Cohesion: 0.03
Nodes (68): accent, action, AppColors, AppTextStyles, AppTheme, background, bodyLg, bodyMd (+60 more)

### Community 5 - "Finance Repository"
Cohesion: 0.03
Nodes (57): amount, amountPaid, cancelEntry, _client, clientId, clientName, correctAmount, createdAt (+49 more)

### Community 6 - "Clients Directory"
Cohesion: 0.03
Nodes (59): _addressCtrl, build, _buildClientList, _buildSearchField, canCreate, client, _ClientCard, _clients (+51 more)

### Community 7 - "User Management"
Cohesion: 0.03
Nodes (56): _allTeams, _assignTeam, _backToTeamPicker, _buildNoTeamState, _buildTeamPicker, _buildTeamView, controller, createState (+48 more)

### Community 8 - "Edge Functions & Service-Role Security"
Cohesion: 0.05
Nodes (52): Backend Security Plan (remove client service-role key), service_role key rotation (only real revocation), Edge Function notify (validated-recipient fan-out), _shared/auth.ts (requireGlobalAdmin / requireSuperAdmin), Service-role Key Removal Blockers, Edge Function admin-reset-app, Edge Function admin-user-ops, PROPOSED_expenses_options.sql (Option A admin-only vs B manager team-scoped) (+44 more)

### Community 9 - "Task Model"
Cohesion: 0.04
Nodes (50): archivedAt, archivedBy, assigneeFor, assignees, authorName, boardColumnId, boardId, clientId (+42 more)

### Community 10 - "Task Repository"
Cohesion: 0.04
Nodes (44): addComment, archiveCompletedTasks, archiveMultipleTasks, archiveTask, archiveTasksByFilter, assignEmployees, buildAuditInsert, _client (+36 more)

### Community 11 - "Create User Flow"
Cohesion: 0.04
Nodes (48): _Banner, build, _buildEmptyEmployees, _buildHeaderCard, _buildNewAccountForm, _buildPromoteTab, _buildTabSelector, color (+40 more)

### Community 12 - "../models/profile_model.dart"
Cohesion: 0.29
Nodes (4): departmentTeamIdFor, RevenueCreateScope, departmentTeamIdFor, TaskCreateScope

### Community 13 - "Company Cash Ledger"
Cohesion: 0.04
Nodes (44): _AdminOnlyNotice, _all, _amountCtrl, _balance, build, _buildActions, _buildBalanceCard, _buildLedger (+36 more)

### Community 14 - "Super Admin Report PDF"
Cohesion: 0.05
Nodes (39): SuperAdminReportData, _applyFilter, build, _buildAttendancePerEmployeeTab, _buildClientDossiersTab, _buildCommentsTab, _buildFilterBar, _buildFinanceTab (+31 more)

### Community 15 - "Client Finance"
Cohesion: 0.05
Nodes (39): CrmEntry, asClient, build, canManage, _client, clientId, color, _confirmDeleteClient (+31 more)

### Community 16 - "Client Repository & Reminders"
Cohesion: 0.04
Nodes (40): adminDb, attendeeIds, attendeeNames, CalEventData, clientId, clientName, ClientRepository, cost (+32 more)

### Community 17 - "Dashboard"
Cohesion: 0.05
Nodes (40): actions, _barSegment, _cashbackWisdoms, _clientCount, createState, dispose, _employees, _EmptyState (+32 more)

### Community 18 - "Notion Table Widget"
Cohesion: 0.04
Nodes (44): _animCtrl, build, _buildAddRow, _buildArchiveBackground, _buildDismissBackground, _buildDraggableRow, _buildEmptyState, _buildHeader (+36 more)

### Community 19 - "notifications_screen.dart"
Cohesion: 0.10
Nodes (17): createState, dispose, _ignoreNotification, initState, _load, _loading, _markAllRead, _markRead (+9 more)

### Community 20 - "Penalties Management"
Cohesion: 0.06
Nodes (34): _AddPenaltyDialog, _AddPenaltyDialogState, _amountCtrl, approvedBy, color, _confirmDelete, createState, currentUserId (+26 more)

### Community 21 - "Shared UI Widgets"
Cohesion: 0.06
Nodes (35): TPriorityBadge, TStatusChip, _AgendaEventTile, _AgendaForDay, _AttendeePicker, _CurrentTimeLine, _DeptContextChip, _DetailRow (+27 more)

### Community 22 - "Router & Routes"
Cohesion: 0.05
Nodes (6): build, _FinanceRouter, icon, makeRouter, message, _PrivilegeDeniedScreen

### Community 23 - "Department Revenue Sheet"
Cohesion: 0.06
Nodes (28): _buildTable, _buildTotals, color, columnLabels, _confirmCancel, _confirmVoid, createState, DepartmentRevenueSheetScreen (+20 more)

### Community 24 - "DB Schema: notify/teams"
Cohesion: 0.12
Nodes (34): public.get_profile_by_email(), public.guard_profile_privileged_fields(), public.init_client_task_visibility(), public.is_global_admin(), public.archive_completed_tasks(), public.assert_super_admin(), public.get_profile_by_email(), public.ai_interactions (+26 more)

### Community 25 - "Workspace Scope"
Cohesion: 0.06
Nodes (27): activeClientTypeFilter, activeDepartmentTeamId, allTeams, _auth, authorizedDepartments, canAccessExpenses, canSwitch, copyWith (+19 more)

### Community 26 - "Team Members"
Cohesion: 0.06
Nodes (31): _addFoundUser, _adding, build, _buildEmptyMembers, createState, dispose, _emailCtrl, _emailRegex (+23 more)

### Community 27 - "Team Performance"
Cohesion: 0.06
Nodes (30): TaskModel, activeCount, assigned, assignmentRejected, AssignmentRejection, at, awaitingAcceptance, awaitingReview (+22 more)

### Community 28 - "WorkspaceScopeNotifier"
Cohesion: 0.08
Nodes (31): TeamFilterNotifier, WorkspaceScopeNotifier, build, DepartmentGateScreen, _apply, build, DepartmentSwitcher, _row (+23 more)

### Community 29 - "Local Notifications"
Cohesion: 0.07
Nodes (22): _alertController, body, _channelHrId, _channelHrName, _channelTaskId, _channelTaskName, _dedupeWindowMs, init (+14 more)

### Community 30 - "Penalty Repository"
Cohesion: 0.07
Nodes (28): amount, applyPenalty, approvedByName, approvePenalty, _client, createPenalty, date, deletePenalty (+20 more)

### Community 31 - "Finance Migrations M1-M3"
Cohesion: 0.11
Nodes (17): idx_crm_entries_source_type, idx_crm_entries_team_id, idx_crm_payments_status, public.crm_entry_corrections, public.crm_payment_audit, crm_entry_amount_guard, crm_payment_overpay_guard, crm_payment_status_sync (+9 more)

### Community 32 - "Auth Session Notifier"
Cohesion: 0.05
Nodes (31): authenticateBiometrics, AuthStatus, _checkSession, completeBiometricPrompt, _department, departmentGatePending, departmentResolution, departmentResolveFailed (+23 more)

### Community 33 - "advanced_analytics_screen.dart"
Cohesion: 0.07
Nodes (26): LocaleController, AdvancedAnalyticsScreen, _AdvancedAnalyticsScreenState, build, createState, _dept, dispose, _empty (+18 more)

### Community 34 - "Team Privileges"
Cohesion: 0.07
Nodes (24): build, _buildBody, _buildCard, _buildSetupRequired, createState, description, icon, initState (+16 more)

### Community 35 - "task table screen"
Cohesion: 0.06
Nodes (30): _applyHidden, build, _buildColumns, _buildRows, _colPrefsKey, _columns, _CommentsCountBadge, count (+22 more)

### Community 36 - "public.events"
Cohesion: 0.12
Nodes (22): event_reminders_pending_idx, events_team_id_idx, public.event_reminders, public.cleanup_event_reminders(), public.notify_event_created(), public.send_event_reminders(), public.tg_event_reset_reminders(), trg_event_reset_reminders (+14 more)

### Community 37 - "main"
Cohesion: 0.07
Nodes (17): TeamPrivilegesNotifier, _load, auth, build, CbToDoApp, _CbToDoAppState, createState, didChangeAppLifecycleState (+9 more)

### Community 38 - "login screen"
Cohesion: 0.12
Nodes (15): _biometricAvailable, _biometricLogin, _checkBiometricAvailable, createState, dispose, _emailCtrl, _errorMsg, _hasStoredCreds (+7 more)

### Community 39 - "settings screen"
Cohesion: 0.05
Nodes (27): ThemeController, _onNotificationTap, initState, build, _biometricEnabled, build, createState, dispose (+19 more)

### Community 40 - "roles editor screen"
Cohesion: 0.08
Nodes (25): _allUsers, canChangeRole, _changeRole, _counts, createState, _error, initState, _isAdmin (+17 more)

### Community 41 - "public.tasks"
Cohesion: 0.09
Nodes (22): public.handoff_task(), public.create_crm_from_task(), public.guard_task_status_transition(), public.notify_fanout(), public.notify_task_status(), public.review_task(), public.submit_task_for_review(), trg_guard_task_status_transition (+14 more)

### Community 42 - "user privileges screen"
Cohesion: 0.08
Nodes (22): build, _buildBody, _buildCard, createState, description, icon, initState, _Item (+14 more)

### Community 43 - "biometric service"
Cohesion: 0.08
Nodes (18): _auth, authenticate, BiometricService, canCheckBiometrics, clearBiometricPreference, clearCredentials, getAvailableBiometrics, hasCredentials (+10 more)

### Community 44 - "mock data"
Cohesion: 0.08
Nodes (23): amount, attendanceSummary, date, doneTasks, expenseCategories, expenses, inProgressTasks, MockData (+15 more)

### Community 45 - "archive completed tasks dialog"
Cohesion: 0.09
Nodes (20): ArchiveCompletedTasksDialog, _ArchiveCompletedTasksDialogState, build, _buildBody, _bulletPoint, _counting, createState, _dateRange (+12 more)

### Community 46 - "team screen"
Cohesion: 0.09
Nodes (17): build, _openClient, _addEmployee, build, _busy, createState, _InactiveBadge, initState (+9 more)

### Community 47 - "company ledger repository"
Cohesion: 0.08
Nodes (23): addFunds, amount, balanceAfter, balanceOf, _client, CompanyLedgerRepository, copyWithBalance, createdAt (+15 more)

### Community 48 - "expense repository"
Cohesion: 0.08
Nodes (23): amount, approvedBy, approveExpense, categoryName, _client, createCategory, createExpense, date (+15 more)

### Community 49 - "team management screen"
Cohesion: 0.09
Nodes (21): build, _buildFirstTimeEmpty, _confirmDelete, createState, icon, initState, label, _load (+13 more)

### Community 50 - "notification repository"
Cohesion: 0.09
Nodes (22): AppNotification, body, _client, createdAt, createNotification, fetchAll, fetchForTeam, fetchForUser (+14 more)

### Community 51 - "dependencies"
Cohesion: 0.09
Nodes (23): dependencies, background_downloader, connectivity_plus, cupertino_icons, firebase_core, firebase_messaging, fl_chart, flutter_local_notifications (+15 more)

### Community 52 - "profile model"
Cohesion: 0.09
Nodes (21): avatarUrl, createdAt, firstName, fromMap, fullName, id, isActive, isAdmin (+13 more)

### Community 53 - "employee performance screen"
Cohesion: 0.10
Nodes (20): build, createState, EmployeePerformanceScreen, _EmployeePerformanceScreenState, _empty, initState, _loadAll, _loading (+12 more)

### Community 54 - "revenue department isolation test"
Cohesion: 0.10
Nodes (13): main, main, _profile, _team, _admin, allTeams, main, scope (+5 more)

### Community 55 - "PUBLIC"
Cohesion: 0.12
Nodes (16): public.list_active_teams(), public.notify_action(), on_attendance_compute_status, public.mark_daily_absentees(), public.tr_compute_attendance_status(), public.send_manual_attendance_reminders(), attendance_reminders_date_idx, attendance_reminders_emp_idx (+8 more)

### Community 56 - "status options manager sheet"
Cohesion: 0.10
Nodes (18): _addOption, adminUserId, build, createState, _deleteOption, _editOption, _hexColor, initState (+10 more)

### Community 57 - "team privileges notifier"
Cohesion: 0.10
Nodes (17): _auth, canCreateEmployees, canManageAttendance, canManageClients, canManageExpenses, canManagePenalties, canManageTasks, canViewFinance (+9 more)

### Community 58 - "task status options repository"
Cohesion: 0.12
Nodes (13): addOption, _cache, _client, colorForStatus, _defaults, deleteOption, _fallback, fetchOptions (+5 more)

### Community 59 - "profile repository"
Cohesion: 0.10
Nodes (19): _client, createUser, deactivateEmployee, fetchAll, fetchByEmail, fetchById, fetchByTeam, fetchEmail (+11 more)

### Community 60 - "AuthNotifier"
Cohesion: 0.10
Nodes (22): AuthNotifier, build, _checking, _checkStatus, createState, PendingApprovalScreen, _PendingApprovalScreenState, _signOut (+14 more)

### Community 61 - "signup screen"
Cohesion: 0.06
Nodes (30): build, createState, dispose, _emailCtrl, _error, ForgotPasswordScreen, _ForgotPasswordScreenState, _FormView (+22 more)

### Community 62 - "team_privileges_model.dart"
Cohesion: 0.13
Nodes (14): canCreateEmployees, canManageAttendance, canManageClients, canManageExpenses, canManagePenalties, canManageTasks, canViewFinance, copyWith (+6 more)

### Community 63 - "splash_screen.dart"
Cohesion: 0.14
Nodes (10): build, _checkBiometricStatus, createState, _ctrl, didChangeDependencies, dispose, _fade, initState (+2 more)

### Community 64 - "task permissions"
Cohesion: 0.11
Nodes (18): canAddComment, canCreateTask, canDeleteTask, canEditAdminFields, canEditFull, canEditProgress, canEditStatus, canReorderTasks (+10 more)

### Community 65 - "push notification service"
Cohesion: 0.11
Nodes (10): _currentUserId, _firebaseMessagingBackgroundHandler, init, _initialized, instance, PushNotificationService, requestNotificationPermission, start (+2 more)

### Community 66 - "department workspace screen"
Cohesion: 0.09
Nodes (13): build, build, children, _CompanyOverviewBanner, departmentCount, _enterDepartment, icon, _iconFor (+5 more)

### Community 67 - "app settings repository"
Cohesion: 0.11
Nodes (17): AppSettingsRepository, _cleanSsidList, clearWorkDataCutoffDate, _client, _decodeSsidList, getWifiSsid, getWifiSsids, getWorkDataCutoffDate (+9 more)

### Community 68 - "team repository"
Cohesion: 0.12
Nodes (15): _client, create, deactivate, delete, fetchAll, fetchAllAdmin, fetchAllStaffAdmin, fetchById (+7 more)

### Community 69 - "package:task_ora/core/models/profile_model.dart"
Cohesion: 0.12
Nodes (8): main, _p, main, _p, main, _p, main, _p

### Community 70 - "public.client_task_visibility"
Cohesion: 0.29
Nodes (3): public.get_profile_by_email(), public.init_client_task_visibility(), public.client_task_visibility

### Community 71 - "client model"
Cohesion: 0.12
Nodes (15): address, ClientModel, clientType, companyName, contactPerson, contractEndDate, contractStartDate, createdAt (+7 more)

### Community 72 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.09
Nodes (8): main, _e, main, main, main, main, main, main

### Community 73 - "index"
Cohesion: 0.30
Nodes (12): DELETE_ORDER, ALLOWED_ORIGINS, corsHeaders(), handle(), withCors(), Caller, getCaller(), httpError() (+4 more)

### Community 75 - "apk update service"
Cohesion: 0.13
Nodes (10): ApkUpdateService, _buildReleaseNotes, checkForUpdates, _checking, _isNewerVersion, _openApk, _showErrorDialog, _showLoadingDialog (+2 more)

### Community 76 - "../../core/models/profile_model.dart"
Cohesion: 0.18
Nodes (8): DashboardQuickActions, showAnalytics, showClients, showTeam, visibleKeys, canChangeStatus, canManage, DeactivationPolicy

### Community 77 - "user privileges model"
Cohesion: 0.13
Nodes (14): canCreateEmployees, canManageAttendance, canManageClients, canManageExpenses, canManagePenalties, canManageTasks, canViewFinance, copyWith (+6 more)

### Community 78 - "dashboard repository"
Cohesion: 0.13
Nodes (13): DashboardRepository, DashboardStats, doneTasks, _fetchAdminScopedStats, fetchStats, inProgressTasks, presentToday, _safeQuery (+5 more)

### Community 79 - "supabase service"
Cohesion: 0.14
Nodes (9): _client, fetchForTeam, save, TeamPrivilegesRepository, _client, fetchForUser, fetchForUserOrDefaults, save (+1 more)

### Community 80 - "start reminder offsets"
Cohesion: 0.13
Nodes (14): allowed, dedupKey, dueAt, error, failed, isAllowed, isDue, label (+6 more)

### Community 81 - "client_detail_screen.dart"
Cohesion: 0.04
Nodes (44): _Activity, build, _buildActivity, _buildCalendar, _buildOverview, children, _client, clientId (+36 more)

### Community 82 - "task model"
Cohesion: 0.14
Nodes (9): compute, done, MontageMonthlyProgress, percent, remaining, target, filter, isVisible (+1 more)

### Community 83 - "realtime service"
Cohesion: 0.14
Nodes (9): _channel, _debounce, _fire, init, instance, listen, RealtimeService, _tables (+1 more)

### Community 84 - "privileged ops"
Cohesion: 0.14
Nodes (11): _c, createUser, deleteUser, fetchEmail, listActiveTeams, notifyAction, PrivilegedOps, resetApp (+3 more)

### Community 85 - "supabase service"
Cohesion: 0.15
Nodes (8): _anonKey, auth, client, currentSession, currentUser, initialize, SupabaseService, _url

### Community 86 - "task_month_visibility_test.dart"
Cohesion: 0.13
Nodes (9): main, _task, main, _task, main, _me, oct, _other (+1 more)

### Community 87 - "department_gate_test.dart"
Cohesion: 0.22
Nodes (5): _isProductionOnly, main, _p, main, _p

### Community 88 - "analytics repository"
Cohesion: 0.15
Nodes (12): AnalyticsRepository, assignees, _client, completion, dueDate, fetchTaskStats, fromMap, isCompleted (+4 more)

### Community 89 - "static const String"
Cohesion: 0.22
Nodes (8): AppRoutes, calendar, dashboard, expenses, login, resolving, tasks, workspaces

### Community 90 - "montage_monthly_progress_test.dart"
Cohesion: 0.25
Nodes (6): _compute, _done, i, main, _now, _t

### Community 91 - "workspace_routing.dart"
Cohesion: 0.22
Nodes (7): departmentGateRedirect, entryRouteFor, guardWorkspaces, isAdminProductionCalendarOnly, isProductionCalendarOnly, productionRedirect, WorkspaceRouting

### Community 92 - "notification trigger service"
Cohesion: 0.17
Nodes (9): ProfileModel, _channel, _hrTypes, instance, NotificationTriggerService, _processedIds, _profile, start (+1 more)

### Community 93 - "team model"
Cohesion: 0.17
Nodes (11): copyWith, createdAt, department, description, fromMap, id, isActive, name (+3 more)

### Community 94 - "List"
Cohesion: 0.17
Nodes (8): clear, _loaded, loadTeams, reload, select, selectedTeam, _selectedTeamId, _teams

### Community 95 - "static const"
Cohesion: 0.18
Nodes (10): AppTime, cairo, _dst, fromCairoToUtc, hm, hm2, _isDst, _lastWeekday (+2 more)

### Community 96 - "public.notifications"
Cohesion: 0.17
Nodes (7): public.send_attendance_reminders(), public.event_recipient_ids(), public.notify_event_created(), public.send_event_reminders(), public.notify_event_created(), on_notification_created_send_fcm, public.notifications

### Community 97 - "monthly_revenue_screen.dart"
Cohesion: 0.05
Nodes (42): CrmPayment, _amt, clientId, ClientMonthlyPaymentsScreen, _ClientMonthlyPaymentsScreenState, clientName, _ClientRevenueCard, color (+34 more)

### Community 98 - "super admin pdf exporter"
Cohesion: 0.18
Nodes (6): _c, _emptyText, exportAndPrintPdf, _kpiBox, _sectionHeader, SuperAdminPdfExporter

### Community 99 - "flutter launcher icons"
Cohesion: 0.18
Nodes (11): flutter_launcher_icons, adaptive_icon_background, adaptive_icon_foreground, android, image_path, ios, min_sdk_android, remove_alpha_ios (+3 more)

### Community 100 - "_"
Cohesion: 0.22
Nodes (7): _, JSNotification, JSNotificationOptions, permission, requestPermission, requestWebNotificationPermission, showWebNotification

### Community 101 - "employee_status_workflow.dart"
Cohesion: 0.29
Nodes (4): allowed, employeeCanSet, EmployeeStatusWorkflow, montageEmployeeOptions

### Community 102 - "app roles"
Cohesion: 0.20
Nodes (9): admin, all, AppRoles, client, employee, manager, staff, superAdmin (+1 more)

### Community 103 - "departments"
Cohesion: 0.22
Nodes (7): _aliases, all, Department, Departments, DepartmentX, fromLabel, fromTeam

### Community 104 - "String?"
Cohesion: 0.20
Nodes (6): isArabic, lang, S, StringL10n, t, tr

### Community 105 - "pubspec.yaml"
Cohesion: 0.20
Nodes (9): description, environment, sdk, flutter, assets, uses-material-design, name, publish_to (+1 more)

### Community 106 - "dark premium"
Cohesion: 0.25
Nodes (6): accent, background, border, card, DarkPremium, onAccent

### Community 107 - "apk download banner"
Cohesion: 0.29
Nodes (6): ApkDownloadBanner, _ApkDownloadBannerState, apkUrl, build, createState, downloadApk

### Community 108 - "archived_tasks_screen.dart"
Cohesion: 0.11
Nodes (16): _archivedTasks, ArchivedTasksScreen, _ArchivedTasksScreenState, build, createState, dispose, initState, _inspectTask (+8 more)

### Community 109 - "core/auth/auth_notifier.dart"
Cohesion: 0.11
Nodes (13): build, createState, dispose, _errorMsg, _handleReset, _obscurePass, _passCtrl, ResetAppDialog (+5 more)

### Community 110 - "sales_sheet_screen.dart"
Cohesion: 0.08
Nodes (21): _addRow, _arabic, build, _busy, _cell, _cellStyle, createState, _deleteRow (+13 more)

### Community 111 - "my_application.cc"
Cohesion: 0.07
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 112 - "department service"
Cohesion: 0.29
Nodes (5): accessibleDepartments, canAccess, canAccessExpenses, DepartmentService, isGlobal

### Community 113 - "currency"
Cohesion: 0.29
Nodes (6): code, compact, egp, egpCompact, _grouped, Money

### Community 114 - "calendar attendee scope"
Cohesion: 0.29
Nodes (6): attendeeAllowed, CalendarAttendeeScope, CalendarDaySpan, coversDay, keepEligible, ownerTeamId

### Community 115 - "task_status_option.dart"
Cohesion: 0.22
Nodes (8): color, columnId, fromMap, id, isDefault, label, position, TaskStatusOption

### Community 116 - "PROPOSED company ledger"
Cohesion: 0.48
Nodes (5): company_ledger_client_token_key, company_ledger_txn_date_idx, public.company_cash_balance(), public.company_ledger, public.company_record_expense()

### Community 117 - "analysis options.yaml"
Cohesion: 0.33
Nodes (5): analyzer, exclude, include, linter, rules

### Community 118 - "monthly_revenue.dart"
Cohesion: 0.08
Nodes (23): _Acc, clientId, clientName, ClientRevenueRow, count, entryCount, _entryYm, _eps (+15 more)

### Community 119 - "index"
Cohesion: 0.33
Nodes (3): NotificationRecord, ServiceAccount, WebhookPayload

### Community 120 - "notification route"
Cohesion: 0.40
Nodes (3): notificationRouteFor, null, refId

### Community 121 - "load token"
Cohesion: 0.40
Nodes (4): begin, isStale, _latest, LoadToken

### Community 122 - "department_gate.dart"
Cohesion: 0.33
Nodes (5): DepartmentGate, DepartmentResolution, isFailed, isPending, isRequired

### Community 124 - "package:flutter/foundation.dart"
Cohesion: 0.25
Nodes (4): android, DefaultFirebaseOptions, ios, web

### Community 125 - "dev dependencies"
Cohesion: 0.40
Nodes (5): dev_dependencies, flutter_launcher_icons, flutter_lints, flutter_test, sdk

### Community 126 - "compilerOptions"
Cohesion: 0.40
Nodes (4): compilerOptions, allowJs, lib, strict

### Community 128 - "static const String"
Cohesion: 0.33
Nodes (4): confirmedStatus, managerCanConfirm, MontageCompletion, pendingStatus

### Community 129 - "package.json"
Cohesion: 0.67
Nodes (3): devDependencies, supabase@^2.121.0, supabase

### Community 130 - "with"
Cohesion: 0.08
Nodes (24): name, runs-on, steps, GITHUB_TOKEN, jobs, build-and-release, name, on (+16 more)

### Community 131 - "Task Handoff — Direct Transfer (Option A): Security Review & Test Matrix"
Cohesion: 0.17
Nodes (11): 1. Role mapping (as approved), 2. Requirement → DB enforcer (verified mapping), 3. Role × action matrix on a TRANSFERRED task (src→dst), 4. Decisions (RESOLVED and implemented), 5. UI implementation (DONE — analyzes clean), 6. Migration execution order (AWAITING your per-file confirmation), 7. Verification evidence (this session), 8. Assumptions (distinct from verified) (+3 more)

### Community 135 - "with"
Cohesion: 0.09
Nodes (20): name, runs-on, steps, jobs, build-ios, name, on, workflow_dispatch (+12 more)

### Community 136 - "Changelog"
Cohesion: 0.10
Nodes (20): [0.1.3](https://github.com/supabase/agent-skills/compare/v0.1.2...v0.1.3) (2026-06-02), [0.1.4](https://github.com/supabase/agent-skills/compare/v0.1.3...v0.1.4) (2026-06-05), [0.1.5](https://github.com/supabase/agent-skills/compare/v0.1.4...v0.1.5) (2026-07-10), [0.1.6](https://github.com/supabase/agent-skills/compare/v0.1.5...supabase-v0.1.6) (2026-07-30), [0.1.7](https://github.com/supabase/agent-skills/compare/v0.1.6...supabase-v0.1.7) (2026-08-12), [0.1.8](https://github.com/supabase/agent-skills/compare/v0.1.7...supabase-v0.1.8) (2026-09-24), [0.1.9](https://github.com/supabase/agent-skills/compare/v0.1.8...supabase-v0.1.9) (2026-09-28), Bug Fixes (+12 more)

### Community 137 - "client_history.dart"
Cohesion: 0.10
Nodes (16): chronological, ClientHistory, compareTo, covers, eventsInMonth, hashCode, initialMonth, month (+8 more)

### Community 138 - "win32_window.cpp"
Cohesion: 0.15
Nodes (8): Point, x, y, Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 139 - "with"
Cohesion: 0.10
Nodes (19): permissions, runs-on, steps, jobs, deploy, name, on, push (+11 more)

### Community 143 - "task_handoff_lock_test.dart"
Cohesion: 0.25
Nodes (6): _dst, main, normal, _src, _task, transferred

### Community 144 - "_gate_sql_guards.mjs"
Cohesion: 0.17
Nodes (7): fail, sql, fail, sql, banned, hits, walk()

### Community 145 - "GATES — Production department: Calendar-only workspace"
Cohesion: 0.33
Nodes (5): Admin in Production workspace = Calendar-only (2026-10-31), Evidence (measured 2026-10-31), Fail-open fix (2026-10-31), Gates, GATES — Production department: Calendar-only workspace

### Community 146 - "sales_sheet_entry.dart"
Cohesion: 0.13
Nodes (14): client, estValue, expectedClose, fromMap, id, lastContact, link, ownerName (+6 more)

### Community 147 - "n8n_service.dart"
Cohesion: 0.20
Nodes (6): getWebhookUrl, N8nService, notifyTaskUpdate, _prefKey, saveWebhookUrl, _statusLabel

### Community 148 - "../../core/models/client_model.dart"
Cohesion: 0.40
Nodes (3): ClientSearch, filter, matches

### Community 150 - "bool get"
Cohesion: 0.12
Nodes (11): isArabic, _kAppLang, _load, _locale, setLanguage, toggleLanguage, _dark, isDark (+3 more)

### Community 173 - "Supabase"
Cohesion: 0.11
Nodes (15): Fix suggestion, Source, What happened, Skill Feedback, Steps, Core Principles, Debugging, Making and Committing Schema Changes (+7 more)

### Community 174 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 175 - "Changelog"
Cohesion: 0.12
Nodes (16): [1.2.0](https://github.com/supabase/agent-skills/compare/v1.1.1...v1.2.0) (2026-06-02), [1.3.0](https://github.com/supabase/agent-skills/compare/v1.2.0...v1.3.0) (2026-06-05), [1.4.0](https://github.com/supabase/agent-skills/compare/v1.3.0...v1.4.0) (2026-07-10), [1.5.0](https://github.com/supabase/agent-skills/compare/supabase-postgres-best-practices-v1.4.0...supabase-postgres-best-practices-v1.5.0) (2026-07-30), [1.6.0](https://github.com/supabase/agent-skills/compare/supabase-postgres-best-practices-v1.5.0...supabase-postgres-best-practices-v1.6.0) (2026-07-30), Bug Fixes, Bug Fixes, Bug Fixes (+8 more)

### Community 176 - "Writing Guidelines for Postgres References"
Cohesion: 0.12
Nodes (15): 1. Concrete Transformation Patterns, 2. Error-First Structure, 3. Quantified Impact, 4. Self-Contained Examples, 5. Semantic Naming, Code Example Standards, Comments, Impact Level Guidelines (+7 more)

### Community 177 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.14
Nodes (13): app_links, connectivity_plus, firebase_core, firebase_messaging, flutter_local_notifications, flutter_secure_storage_macos, Foundation, local_auth_darwin (+5 more)

### Community 178 - "win32_window.cpp"
Cohesion: 0.14
Nodes (6): EnableFullDpiSupportIfAvailable(), EnableNonClientDpiScaling, Win32Window, child_content_, quit_on_close_, window_handle_

### Community 179 - "utils.cpp"
Cohesion: 0.12
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 180 - "manifest.json"
Cohesion: 0.17
Nodes (11): background_color, description, display, gcm_sender_id, icons, name, orientation, prefer_related_applications (+3 more)

### Community 181 - "State"
Cohesion: 0.10
Nodes (30): _ColumnOptionsSheet, _ColumnOptionsSheetState, NotionTable, _NotionTableState, _AddEventSheet, _AddEventSheetState, CalendarScreen, _CalendarScreenState (+22 more)

### Community 182 - "Section Definitions"
Cohesion: 0.20
Nodes (9): 1. Query Performance (query), 2. Connection Management (conn), 3. Security & RLS (security), 4. Schema Design (schema), 5. Concurrency & Locking (lock), 6. Data Access Patterns (data), 7. Monitoring & Diagnostics (monitor), 8. Advanced Features (advanced) (+1 more)

### Community 185 - "bottom_nav_shell.dart"
Cohesion: 0.09
Nodes (14): CalendarEventScope, eventTypeForDepartment, isBookingDepartment, _allItems, BottomNavShell, _BottomNavShellState, build, _clientBranchIndices (+6 more)

### Community 186 - "task_handoff_lock.dart"
Cohesion: 0.15
Nodes (10): matches, MontageTaskFilter, canAssign, canDelete, canEditDefinition, canHandoff, canTrackStatus, isLocked (+2 more)

### Community 187 - "tavatar_test.dart"
Cohesion: 0.40
Nodes (3): main, _pump, pumpWidget

### Community 188 - "revenue_monthly_test.dart"
Cohesion: 0.22
Nodes (5): main, _row, _entry, main, _pay

### Community 190 - "ios/RunnerTests/RunnerTests.swift"
Cohesion: 0.32
Nodes (4): Flutter, SceneDelegate, UIKit, XCTest

### Community 192 - "FlutterMacOS"
Cohesion: 0.38
Nodes (3): Cocoa, FlutterMacOS, RunnerTests

### Community 193 - "team_performance_test.dart"
Cohesion: 0.29
Nodes (4): main, _emp, main, _task

### Community 194 - "Supabase Postgres Best Practices"
Cohesion: 0.33
Nodes (5): How to Use, References, Rule Categories by Priority, Supabase Postgres Best Practices, When to Apply

### Community 196 - "GATES — Task Handoff: Direct Transfer (Option A)"
Cohesion: 0.50
Nodes (3): Evidence (measured 2026-10-31, after sender-dept + C1 team-check + UI gating), Gates, GATES — Task Handoff: Direct Transfer (Option A)

### Community 197 - "client_search_test.dart"
Cohesion: 0.33
Nodes (3): _c, clients, main

### Community 239 - "Size"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 245 - "sales_sheet_repository.dart"
Cohesion: 0.18
Nodes (8): addRow, _client, deleteRow, _editable, fetchAll, SalesSheetRepository, _table, updateField

### Community 249 - "PROPOSED_sales_sheet_entries.sql"
Cohesion: 0.70
Nodes (4): public.sales_sheet_entries, public.tg_sales_sheet_touch(), sales_sheet_entries_sort_idx, trg_sales_sheet_touch

## Knowledge Gaps
- **2369 isolated node(s):** `TaskStatusOption`, `id`, `columnId`, `label`, `color` (+2364 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 2973 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **92 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AuthNotifier` connect `AuthNotifier` to `Calendar & Attendees`, `Task Board & Filters`, `Task Detail & Assignment`, `Clients Directory`, `User Management`, `Create User Flow`, `Super Admin Report PDF`, `Dashboard`, `notifications_screen.dart`, `Penalties Management`, `Router & Routes`, `Department Revenue Sheet`, `Workspace Scope`, `WorkspaceScopeNotifier`, `Auth Session Notifier`, `advanced_analytics_screen.dart`, `task table screen`, `main`, `login screen`, `settings screen`, `roles editor screen`, `user privileges screen`, `archive completed tasks dialog`, `team screen`, `team management screen`, `State`, `_TaskBoardScreenState`, `_ClientsScreenState`, `team privileges notifier`, `signup screen`, `splash_screen.dart`, `_CreateTaskSheetState`, `archived_tasks_screen.dart`, `core/auth/auth_notifier.dart`, `sales_sheet_screen.dart`, `_AdminDashboardScreenState`, `_EditEmployeeSheetState`, `_UserCardState`, `build`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **What connects `TaskStatusOption`, `id`, `columnId` to the rest of the system?**
  _2369 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Calendar & Attendees` be split into smaller, more focused modules?**
  _Cohesion score 0.015151515151515152 - nodes in this community are weakly interconnected._
- **Why does `ProfileModel` connect `notification trigger service` to `Auth Session Notifier`, `task permissions`, `Calendar & Attendees`, `Task Board & Filters`, `User Management`, `roles editor screen`, `user privileges screen`, `Create User Flow`, `Dashboard`, `profile model`, `Workspace Scope`, `Team Members`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Should `Super Admin Reports` be split into smaller, more focused modules?**
  _Cohesion score 0.015748031496062992 - nodes in this community are weakly interconnected._
- **Why does `Win32Window` connect `win32_window.cpp` to `win32_window.cpp`, `utils.cpp`, `FlutterWindow`, `Size`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `Task Board & Filters` be split into smaller, more focused modules?**
  _Cohesion score 0.01639344262295082 - nodes in this community are weakly interconnected._