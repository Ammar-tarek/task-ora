// lib/features/tasks/task_board_screen.dart
// Role-aware task board: table view + kanban view.
// Column set and available actions adapt to admin / manager / employee / client.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/providers/theme_controller.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/task_status_options_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/models/task_model.dart';
import '../../core/models/team_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/models/client_model.dart';
import '../../core/models/task_status_option.dart';
import 'status_options_manager_sheet.dart';
import '../../core/utils/task_permissions.dart';
import '../../core/utils/app_time.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/notion_table.dart';
import '../../core/widgets/team_filter_chip.dart';
import 'task_detail_sheet.dart';

class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({super.key, this.initialFilter});
  final String? initialFilter;

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

enum _Sort { newest, oldest, dueDate, priorityHigh, clientAZ, titleAZ, moved }

class _TaskBoardScreenState extends State<TaskBoardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';

  // ── Monthly workspace ──────────────────────────────────────────────────────
  // The active month is a pure VIEW/FILTER context. Switching it (manually or
  // via automatic calendar rollover) never mutates, moves, or deletes any task.
  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);
  // The real current calendar month (Egypt time). Updated on rollover.
  DateTime _liveMonth = _monthOf(AppTime.now());
  // The month currently being viewed. Defaults to the real current month.
  DateTime _activeMonth = _monthOf(AppTime.now());
  Timer? _rolloverTimer;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  String _monthLabel(DateTime m) => '${_monthNames[m.month - 1]} ${m.year}';
  String _search = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  _Sort _sort = _Sort.newest;
  String? _clientId; // null = all clients
  String? _assigneeId; // null = all assignees
  bool _isTableView = true;
  final ScrollController _boardHorizontalController = ScrollController();

  // Multi-selection state for Super Admin / Admin batch operations
  bool _isSelectionMode = false;
  Set<String> _selectedTaskIds = {};

  ProfileModel? _profile;
  TaskPermissions? _perms;

  final List<NotionColumn> _customColumns = [];
  TeamFilterNotifier? _teamFilter;
  List<TeamModel> _teams = []; // for department handoff picker + names

  static const _statusFilters = [
    'All',
    'To Do',
    'In Progress',
    'Employee Done',
    'Client Approved',
    'Client Rejected',
    'Completed',
    'On Hold',
  ];
  static const _statusMap = <String, String>{
    'To Do': 'not_started',
    'In Progress': 'in_progress',
    'Employee Done': 'employee_done',
    'Client Approved': 'client_approved',
    'Client Rejected': 'client_rejected',
    'Completed': 'completed',
    'On Hold': 'on_hold',
  };
  static const _priorityWeight = <String, int>{
    'critical': 4,
    'high': 3,
    'medium': 2,
    'low': 1,
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null &&
        _statusFilters.contains(widget.initialFilter)) {
      _filter = widget.initialFilter!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _teamFilter = context.read<TeamFilterNotifier>()
        ..loadTeams()
        ..addListener(_onTeamChange);
      _load();
    });
    // Live refresh when tasks change anywhere.
    RealtimeService.instance.listen(const [
      'tasks',
      'task_assignees',
    ], _onRealtime);
    // Automatic month rollover: detect when the real calendar month changes
    // while the app is open, and follow it if the user is on the live month.
    WidgetsBinding.instance.addObserver(this);
    _rolloverTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkMonthRollover(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkMonthRollover();
  }

  /// Detect a real calendar-month change and, if the user is still viewing the
  /// previously-live month, follow the calendar to the new month. Historical /
  /// future months the user manually navigated to are left untouched. This only
  /// changes the viewing context and reloads — it never modifies task data.
  void _checkMonthRollover() {
    if (!mounted) return;
    final nowMonth = _monthOf(AppTime.now());
    if (nowMonth == _liveMonth) return;
    final wasOnLiveMonth = _activeMonth == _liveMonth;
    setState(() {
      _liveMonth = nowMonth;
      if (wasOnLiveMonth) _activeMonth = nowMonth;
    });
    if (wasOnLiveMonth) _load(animate: false);
  }

  void _goToMonth(DateTime m) {
    final target = _monthOf(m);
    if (target == _activeMonth) return;
    setState(() => _activeMonth = target);
  }

  @override
  void didUpdateWidget(TaskBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != null &&
        _statusFilters.contains(widget.initialFilter)) {
      setState(() {
        _filter = widget.initialFilter!;
      });
    }
  }

  void _onRealtime() {
    if (mounted) _load(animate: false);
  }

  @override
  void dispose() {
    _rolloverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _boardHorizontalController.dispose();
    _searchController.dispose();
    RealtimeService.instance.unlisten(_onRealtime);
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onTeamChange() {
    if (mounted) _load(animate: false);
  }

  // ── Derived client / assignee maps from loaded tasks ────────────────────────

  Map<String, String> get _clientOptions {
    final map = <String, String>{};
    for (final t in _tasks) {
      if (t.clientId != null && t.clientName != null) {
        map[t.clientId!] = t.clientName!;
      }
    }
    return map;
  }

  Map<String, String> get _assigneeOptions {
    final map = <String, String>{};
    for (final t in _tasks) {
      for (final a in t.assignees) {
        map[a.profileId] = a.fullName;
      }
    }
    return map;
  }

  // ── Filtered + sorted list ───────────────────────────────────────────────────

  // Tasks pending a department handoff — shown only in the Waiting List.
  List<TaskModel> get _waiting {
    final mine = _tasks.where((t) => t.handoffToTeamId != null).toList();
    if (_profile?.isAdmin == true) return mine;
    final myTeam = _profile?.teamId;
    return mine.where((t) => t.handoffToTeamId == myTeam).toList();
  }

  List<TaskModel> get _filtered {
    // Exclude pending-handoff tasks — they live in the Waiting List only.
    var list = List<TaskModel>.of(
      _tasks.where((t) => t.handoffToTeamId == null),
    );

    // Month workspace — primary context. Show only tasks anchored to the
    // active month (by due date, else creation date). Pure view filter.
    list = list.where((t) => t.monthAnchor == _activeMonth).toList();

    // Status filter
    if (_filter != 'All') {
      final key = _statusMap[_filter] ?? '';
      list = list.where((t) => t.status == key).toList();
    }

    // Client filter
    if (_clientId != null) {
      list = list.where((t) => t.clientId == _clientId).toList();
    }

    // Assignee filter
    if (_assigneeId != null) {
      list = list
          .where((t) => t.assignees.any((a) => a.profileId == _assigneeId))
          .toList();
    }

    // Search filter — title, client, assignee names, description
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((t) {
        final hay = <String>[
          t.title,
          t.clientName ?? '',
          t.description ?? '',
          ...t.assignees.map((a) => a.fullName),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }

    // Sort
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _Sort.dueDate:
        list.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      case _Sort.priorityHigh:
        list.sort(
          (a, b) => (_priorityWeight[b.priority] ?? 0).compareTo(
            _priorityWeight[a.priority] ?? 0,
          ),
        );
      case _Sort.clientAZ:
        list.sort((a, b) => (a.clientName ?? '').compareTo(b.clientName ?? ''));
      case _Sort.titleAZ:
        list.sort((a, b) => a.title.compareTo(b.title));
      case _Sort.moved:
        // Moved (handed-off) tasks first, newest among them.
        list.sort((a, b) {
          final am = a.handoffFromTeamId != null ? 1 : 0;
          final bm = b.handoffFromTeamId != null ? 1 : 0;
          if (am != bm) return bm - am;
          return b.createdAt.compareTo(a.createdAt);
        });
    }

    return list;
  }

  String get _sortLabel {
    switch (_sort) {
      case _Sort.newest:
        return S.t('newest_first');
      case _Sort.oldest:
        return S.t('oldest_first');
      case _Sort.dueDate:
        return S.t('due_date');
      case _Sort.priorityHigh:
        return S.t('priority_high_low');
      case _Sort.clientAZ:
        return S.t('client_az');
      case _Sort.titleAZ:
        return S.t('title_az');
      case _Sort.moved:
        return S.t('moved_tasks');
    }
  }

  bool get _hasActiveFilters =>
      _filter != 'All' ||
      _clientId != null ||
      _assigneeId != null ||
      _search.trim().isNotEmpty ||
      _sort != _Sort.newest;

  // ── Role-based columns ────────────────────────────────────────────────────

  List<NotionColumn> get _columns {
    final p = _perms;
    return [
      NotionColumn(
        key: 'title',
        label: S.t('task'),
        icon: Icons.text_fields,
        flex: 3,
      ),
      NotionColumn(
        key: 'status',
        label: S.t('status'),
        icon: Icons.circle_outlined,
        flex: 2,
      ),
      if (p?.canSeePriority != false)
        NotionColumn(
          key: 'priority',
          label: S.t('priority'),
          icon: Icons.flag_outlined,
          flex: 2,
        ),
      if (p?.canSeeAssignees != false)
        NotionColumn(
          key: 'assignee',
          label: S.t('assignee'),
          icon: Icons.person_outline,
          flex: 2,
        ),
      NotionColumn(
        key: 'due',
        label: S.t('due'),
        icon: Icons.calendar_today_outlined,
        flex: 2,
      ),
      if (p?.canSeeProgress != false)
        NotionColumn(
          key: 'progress',
          label: S.t('progress'),
          icon: Icons.trending_up,
          flex: 2,
        ),
      if (p?.canSeeCost == true)
        NotionColumn(
          key: 'cost',
          label: S.t('cost_price'),
          icon: Icons.monetization_on_outlined,
          flex: 2,
        ),
      if (p?.canSeeComments == true)
        NotionColumn(
          key: 'comments',
          label: S.t('comments'),
          icon: Icons.comment_outlined,
          flex: 1,
        ),
      ..._customColumns,
    ];
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool animate = true, int attempt = 0}) async {
    if (animate) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = context.read<AuthNotifier>().profile;

      // Cold start / biometric unlock: the Supabase session + profile may still
      // be resolving when this first fires. Keep the spinner and retry instead
      // of flashing "Error loading tasks" until the retry succeeds.
      if (profile == null) {
        if (attempt < 6 && mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          return _load(animate: false, attempt: attempt + 1);
        }
      }

      _profile = profile;
      _perms = profile != null ? TaskPermissions(profile) : null;

      String? overrideTeamId;
      if (profile?.isAdmin == true) {
        overrideTeamId = context.read<TeamFilterNotifier>().selectedTeamId;
      }

      final data = profile != null
          ? await TaskRepository.fetchTasksForProfile(
              profile,
              overrideTeamId: overrideTeamId,
            )
          : [];
      // Teams list (for handoff target picker + department names).
      if (_teams.isEmpty && profile?.isClient != true) {
        try {
          _teams = await TeamRepository.fetchAllAdmin();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _tasks = data as List<TaskModel>;
          _loading = false;
        });
      }
    } catch (e) {
      // A first-load failure right after cold start is usually the access token
      // still refreshing — retry a few times before surfacing the error.
      if (attempt < 3 && mounted) {
        await Future.delayed(const Duration(milliseconds: 600));
        return _load(animate: false, attempt: attempt + 1);
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Row builder ───────────────────────────────────────────────────────────

  List<NotionRow> _buildRows() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final titleStyle = isMobile
        ? AppTextStyles.labelMd.copyWith(fontSize: 11)
        : AppTextStyles.labelMd;
    final dataStyle = isMobile
        ? AppTextStyles.dataSm.copyWith(fontSize: 10)
        : AppTextStyles.dataSm;
    final bodyStyle = isMobile
        ? AppTextStyles.bodySm.copyWith(fontSize: 10)
        : AppTextStyles.bodySm;
    final avatarSize = isMobile ? 16.0 : 20.0;

    return _filtered.map((t) {
      final Map<String, Widget> cells = {
        'title': Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.title,
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (t.clientName != null)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  t.clientName!,
                  style: bodyStyle.copyWith(
                    fontSize: 9,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        'status': FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: TStatusChip(
            label: t.statusLabel,
            color: _statusColor(t.status),
          ),
        ),
        if (_perms?.canSeePriority != false)
          'priority': FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: TPriorityBadge(priority: t.priorityLabel),
          ),
        if (_perms?.canSeeAssignees != false)
          'assignee': Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TAvatar(name: t.leadAssigneeName, size: avatarSize),
              SizedBox(width: isMobile ? 3 : 5),
              Flexible(
                child: Text(
                  t.leadAssigneeName,
                  style: bodyStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        'due': Text(t.dueDateDisplay, style: dataStyle),
        if (_perms?.canSeeProgress != false)
          'progress': _ProgressCell(pct: t.completionPercentage),
        if (_perms?.canSeeCost == true)
          'cost': Text(
            t.cost != null ? 'EGP ${t.cost!.toStringAsFixed(2)}' : '—',
            style: dataStyle.copyWith(color: AppColors.gold),
          ),
        if (_perms?.canSeeComments == true)
          'comments': _CommentsCountBadge(count: t.comments.length),
      };
      for (final cc in _customColumns) {
        cells[cc.key] = Text('—', style: bodyStyle);
      }
      return NotionRow(id: t.id, cells: cells);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return AppColors.statusInProgress;
      case 'employee_done':
        return AppColors.statusMedium;
      case 'client_approved':
        return AppColors.statusDone;
      case 'client_rejected':
        return AppColors.error;
      case 'completed':
        return AppColors.statusDone;
      case 'on_hold':
        return AppColors.outline;
      default:
        return AppColors.statusTodo;
    }
  }

  // ── Sort / filter dialogs & actions ────────────────────────────────────────

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sort tasks', style: AppTextStyles.headlineSm),
                ),
              ),
              const SizedBox(height: 8),
              ..._Sort.values.map((s) {
                final labels = {
                  _Sort.newest: 'Newest first',
                  _Sort.oldest: 'Oldest first',
                  _Sort.dueDate: 'Due date (soonest)',
                  _Sort.priorityHigh: 'Priority (high → low)',
                  _Sort.clientAZ: 'Client (A – Z)',
                  _Sort.titleAZ: 'Title (A – Z)',
                  _Sort.moved: 'Moved tasks',
                };
                final icons = {
                  _Sort.newest: Icons.arrow_downward,
                  _Sort.oldest: Icons.arrow_upward,
                  _Sort.dueDate: Icons.calendar_today_outlined,
                  _Sort.priorityHigh: Icons.flag_outlined,
                  _Sort.clientAZ: Icons.business_outlined,
                  _Sort.titleAZ: Icons.sort_by_alpha,
                  _Sort.moved: Icons.swap_horiz,
                };
                return ListTile(
                  leading: Icon(icons[s], size: 20, color: AppColors.gold),
                  title: Text(labels[s]!, style: AppTextStyles.bodyMd),
                  trailing: _sort == s
                      ? const Icon(Icons.check, color: AppColors.gold, size: 18)
                      : null,
                  onTap: () {
                    setState(() => _sort = s);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showClientFilterSheet() {
    final opts = _clientOptions;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Filter by client',
                    style: AppTextStyles.headlineSm,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.people_outline,
                  size: 20,
                  color: AppColors.gold,
                ),
                title: Text('All clients', style: AppTextStyles.bodyMd),
                trailing: _clientId == null
                    ? const Icon(Icons.check, color: AppColors.gold, size: 18)
                    : null,
                onTap: () {
                  setState(() => _clientId = null);
                  Navigator.pop(context);
                },
              ),
              if (opts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    'No client-linked tasks loaded.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...opts.entries.map(
                  (e) => ListTile(
                    leading: Icon(
                      Icons.business_outlined,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    title: Text(e.value, style: AppTextStyles.bodyMd),
                    trailing: _clientId == e.key
                        ? const Icon(Icons.check, color: AppColors.gold, size: 18)
                        : null,
                    onTap: () {
                      setState(() => _clientId = e.key);
                      Navigator.pop(context);
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showAssigneeFilterSheet() {
    final opts = _assigneeOptions;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Filter by assignee',
                    style: AppTextStyles.headlineSm,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.group_outlined,
                  size: 20,
                  color: AppColors.gold,
                ),
                title: Text('All assignees', style: AppTextStyles.bodyMd),
                trailing: _assigneeId == null
                    ? const Icon(Icons.check, color: AppColors.gold, size: 18)
                    : null,
                onTap: () {
                  setState(() => _assigneeId = null);
                  Navigator.pop(context);
                },
              ),
              if (opts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    'No assigned tasks loaded.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...opts.entries.map(
                  (e) => ListTile(
                    leading: TAvatar(name: e.value, size: 24),
                    title: Text(e.value, style: AppTextStyles.bodyMd),
                    trailing: _assigneeId == e.key
                        ? const Icon(Icons.check, color: AppColors.gold, size: 18)
                        : null,
                    onTap: () {
                      setState(() => _assigneeId = e.key);
                      Navigator.pop(context);
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _archiveTaskRow(String id) async {
    final profile = _profile;
    if (profile == null) return;
    final ok = await TaskRepository.archiveTask(id, profileId: profile.id);
    if (ok) {
      setState(() {
        _tasks.removeWhere((t) => t.id == id);
        _selectedTaskIds.remove(id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task archived')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to archive task')),
        );
        _load();
      }
    }
  }

  Future<void> _archiveSelectedTasks() async {
    final profile = _profile;
    if (profile == null || _selectedTaskIds.isEmpty) return;

    final count = _selectedTaskIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Selected Tasks'),
        content: Text('Are you sure you want to archive $count selected task(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Archive All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final idsToArchive = _selectedTaskIds.toList();
    final ok = await TaskRepository.archiveMultipleTasks(
      idsToArchive,
      profileId: profile.id,
    );

    if (ok) {
      setState(() {
        _tasks.removeWhere((t) => idsToArchive.contains(t.id));
        _selectedTaskIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count task(s) archived successfully!')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to archive selected tasks.')),
        );
        _load();
      }
    }
  }

  Future<void> _changeSelectedTasksStatus() async {
    final profile = _profile;
    if (profile == null || _selectedTaskIds.isEmpty) return;

    final count = _selectedTaskIds.length;

    final chosenStatusKey = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Change status for $count task(s)',
                  style: AppTextStyles.headlineSm,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.circle_outlined, color: Colors.blue),
                title: const Text('To Do'),
                onTap: () => Navigator.pop(context, 'not_started'),
              ),
              ListTile(
                leading: const Icon(Icons.loop, color: AppColors.gold),
                title: const Text('In Progress'),
                onTap: () => Navigator.pop(context, 'in_progress'),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in, color: Colors.orange),
                title: const Text('Employee Done'),
                onTap: () => Navigator.pop(context, 'employee_done'),
              ),
              ListTile(
                leading: const Icon(Icons.verified, color: Colors.teal),
                title: const Text('Client Approved'),
                onTap: () => Navigator.pop(context, 'client_approved'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                title: const Text('Client Rejected'),
                onTap: () => Navigator.pop(context, 'client_rejected'),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: AppColors.statusDone),
                title: const Text('Completed'),
                onTap: () => Navigator.pop(context, 'completed'),
              ),
              ListTile(
                leading: const Icon(Icons.pause_circle_outline, color: Colors.purple),
                title: const Text('On Hold'),
                onTap: () => Navigator.pop(context, 'on_hold'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (chosenStatusKey == null) return;

    final idsToUpdate = _selectedTaskIds.toList();
    final errorMsg = await TaskRepository.updateMultipleTasksStatus(
      idsToUpdate,
      chosenStatusKey,
      profileId: profile.id,
    );

    if (errorMsg == null) {
      setState(() {
        _selectedTaskIds.clear();
        _isSelectionMode = false;
      });
      await _load(animate: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count task(s) status updated!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $errorMsg'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
        _load();
      }
    }
  }

  Future<void> _moveSelectedTasksToDepartment() async {
    final profile = _profile;
    if (profile == null || _selectedTaskIds.isEmpty) return;

    final selectedTasks = _tasks
        .where((t) => _selectedTaskIds.contains(t.id))
        .toList();
    if (selectedTasks.isEmpty) return;

    final count = selectedTasks.length;

    // Fetch all active departments/teams across the organization
    List<TeamModel> allTeams = [];
    try {
      allTeams = await TeamRepository.fetchAllAdmin(activeOnly: true);
    } catch (_) {}
    if (allTeams.isEmpty) {
      allTeams = _teams;
    }
    if (!mounted) return;
    final targets = allTeams.toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other department to hand off to.')),
      );
      return;
    }

    final picked = await showModalBottomSheet<TeamModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Move $count task(s) to department',
                  style: AppTextStyles.headlineSm,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              ...targets.map(
                (t) => ListTile(
                  leading: const Icon(
                    Icons.apartment_outlined,
                    color: AppColors.gold,
                  ),
                  title: Text(
                    t.department ?? t.name,
                    style: AppTextStyles.labelMd,
                  ),
                  subtitle: Text('Team: ${t.name}', style: AppTextStyles.bodySm),
                  onTap: () => Navigator.pop(context, t),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;

    final errorMsg = await TaskRepository.handoffMultipleTasks(
      selectedTasks,
      toTeamId: picked.id,
      byProfileId: profile.id,
      defaultFromTeamId: profile.teamId,
    );

    if (errorMsg == null) {
      setState(() {
        _selectedTaskIds.clear();
        _isSelectionMode = false;
      });
      await _load(animate: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count task(s) sent to ${picked.department ?? picked.name} — waiting for their manager.',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move selected tasks: $errorMsg'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
        _load();
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _filter = 'All';
      _clientId = null;
      _assigneeId = null;
      _search = '';
      _searchController.clear();
      _sort = _Sort.newest;
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.select<ThemeController, bool>((t) => t.isDark);
    context.select<LocaleController, Locale>((l) => l.locale);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Column(
        children: [
          _buildMonthBar(),
          const TeamFilterChip(),
          if (_showSearch) _buildSearchBar(),
          if (_isSelectionMode) _buildSelectionBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ── Sub-build Layout Helpers ────────────────────────────────────────────────

  static DateTime _addMonths(DateTime m, int delta) =>
      DateTime(m.year, m.month + delta);

  // Total tasks anchored to the active month (ignores status/client/assignee/
  // search filters — the workspace's true size). Excludes pending handoffs.
  int get _monthTaskCount => _tasks
      .where((t) => t.handoffToTeamId == null && t.monthAnchor == _activeMonth)
      .length;

  // ── Monthly workspace navigation bar ────────────────────────────────────────
  Widget _buildMonthBar() {
    final prev = _addMonths(_activeMonth, -1);
    final next = _addMonths(_activeMonth, 1);
    final offCurrent = _activeMonth != _liveMonth;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 22,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () => _goToMonth(prev),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MonthPill(
                    label: _monthLabel(prev),
                    active: false,
                    onTap: () => _goToMonth(prev),
                  ),
                  const SizedBox(width: 6),
                  _MonthPill(
                    label: _monthLabel(_activeMonth),
                    active: true,
                    isLive: _activeMonth == _liveMonth,
                    onTap: () {},
                  ),
                  const SizedBox(width: 6),
                  _MonthPill(
                    label: _monthLabel(next),
                    active: false,
                    onTap: () => _goToMonth(next),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 22,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: () => _goToMonth(next),
          ),
          if (!_loading)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Text(
                '$_monthTaskCount ${_monthTaskCount == 1 ? 'task' : 'tasks'}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          if (offCurrent)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: const Icon(Icons.today_outlined, color: AppColors.gold),
              tooltip: 'Back to current month',
              onPressed: () => _goToMonth(_liveMonth),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (v) => setState(() => _search = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMd,
        decoration: InputDecoration(
          isDense: true,
          hintText: S.t('search_tasks'),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.gold),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          _isTableView
              ? '${S.t('tasks')} — ${S.t('task_table')}'
              : '${S.t('tasks')} — ${S.t('task_board')}',
          key: ValueKey(_isTableView),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showSearch ? Icons.search_off : Icons.search,
            color: _showSearch ? AppColors.gold : null,
          ),
          tooltip: _showSearch ? 'Hide search' : 'Search tasks',
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _search = '';
                _searchController.clear();
              }
            });
          },
        ),
        if (_profile?.isAdmin == true ||
            _profile?.isSuperAdmin == true ||
            _profile?.isManager == true)
          IconButton(
            icon: Icon(
              _isSelectionMode
                  ? Icons.check_box
                  : Icons.check_box_outlined,
              color: _isSelectionMode ? AppColors.gold : null,
            ),
            tooltip: _isSelectionMode
                ? 'Exit selection mode'
                : 'Select multiple tasks',
            onPressed: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) _selectedTaskIds.clear();
              });
            },
          ),
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween(begin: 0.5, end: 1.0).animate(anim),
              child: child,
            ),
            child: Icon(
              _isTableView
                  ? Icons.view_kanban_outlined
                  : Icons.table_rows_outlined,
              key: ValueKey(_isTableView),
            ),
          ),
          tooltip: _isTableView ? 'Board view' : 'Table view',
          onPressed: () => setState(() => _isTableView = !_isTableView),
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget? _buildFab() {
    if (_perms?.canCreateTask == false) return null;
    return FloatingActionButton(
      onPressed: () => _showCreateSheet(context),
      backgroundColor: AppColors.primary,
      child: const Icon(Icons.add, color: AppColors.gold),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoadingView();
    if (_error != null) return _buildErrorView();

    final canManage = _profile?.isAdmin == true || _profile?.isManager == true;
    final waiting = _waiting;

    return Column(
      children: [
        if (canManage && waiting.isNotEmpty)
          _WaitingList(
            tasks: waiting,
            teamName: _teamName,
            onAccept: _acceptHandoff,
            onReject: _rejectHandoff,
            onView: _openWaitingDetail,
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.03, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _isTableView
                ? _buildTableView(key: const ValueKey('table'))
                : _buildBoardView(key: const ValueKey('board')),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.gold),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: AppColors.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text('Error loading tasks', style: AppTextStyles.labelMd),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildSelectionBanner() {
    final count = _selectedTaskIds.length;
    final isAdmin = _profile?.isAdmin == true || _profile?.isSuperAdmin == true;

    return Container(
      width: double.infinity,
      color: AppColors.gold.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_box_outlined, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Text(
            '$count selected',
            style: AppTextStyles.labelMd.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        if (_selectedTaskIds.length == _filtered.length) {
                          _selectedTaskIds.clear();
                        } else {
                          _selectedTaskIds =
                              _filtered.map((t) => t.id).toSet();
                        }
                      });
                    },
                    icon: Icon(
                      _selectedTaskIds.length == _filtered.length
                          ? Icons.deselect
                          : Icons.select_all,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    label: Text(
                      _selectedTaskIds.length == _filtered.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(color: AppColors.gold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: count > 0 ? _changeSelectedTasksStatus : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text('Change Status ($count)'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed:
                        count > 0 ? _moveSelectedTasksToDepartment : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.gold,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.apartment_outlined, size: 18),
                    label: Text('Move Dept ($count)'),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: count > 0 ? _archiveSelectedTasks : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        foregroundColor: AppColors.gold,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: Text('Archive ($count)'),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedTaskIds.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _teamName(String? teamId) {
    if (teamId == null) return '—';
    final t = _teams.where((t) => t.id == teamId);
    return t.isEmpty ? 'Other dept' : t.first.name;
  }

  void _openWaitingDetail(TaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TaskDetailSheet(
        taskId: task.id,
        onUpdated: () => _load(animate: false),
        onAcceptHandoff: () => _acceptHandoff(task),
        onRejectHandoff: () => _rejectHandoff(task),
      ),
    );
  }

  Future<void> _acceptHandoff(TaskModel task) async {
    final targetTeam = task.handoffToTeamId ?? _profile?.teamId;
    if (targetTeam == null) return;
    await TaskRepository.acceptHandoff(taskId: task.id, teamId: targetTeam);
    await _load(animate: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task accepted. Open it to assign your team.'),
          backgroundColor: AppColors.statusDone,
        ),
      );
    }
  }

  Future<void> _rejectHandoff(TaskModel task) async {
    await TaskRepository.rejectHandoff(taskId: task.id);
    await _load(animate: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task handoff rejected and returned to original department.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _moveToDepartment(TaskModel task) async {
    final sourceTeam = task.teamId ?? _profile?.teamId;
    List<TeamModel> allTeams = [];
    try {
      allTeams = await TeamRepository.fetchAllAdmin(activeOnly: true);
    } catch (_) {}
    if (allTeams.isEmpty) {
      allTeams = _teams;
    }
    if (!mounted) return;
    final targets = allTeams.where((t) => t.id != sourceTeam).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other department to hand off to.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<TeamModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Move to department',
                  style: AppTextStyles.headlineSm,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              ...targets.map(
                (t) => ListTile(
                  leading: const Icon(
                    Icons.apartment_outlined,
                    color: AppColors.gold,
                  ),
                  title: Text(
                    t.department ?? t.name,
                    style: AppTextStyles.labelMd,
                  ),
                  subtitle: Text('Team: ${t.name}', style: AppTextStyles.bodySm),
                  onTap: () => Navigator.pop(context, t),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (picked == null || sourceTeam == null) return;
    await TaskRepository.handoffTask(
      taskId: task.id,
      fromTeamId: sourceTeam,
      toTeamId: picked.id,
      byProfileId: _profile!.id,
    );
    await _load(animate: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent to ${picked.department ?? picked.name} — waiting for their manager.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Widget _buildSortFilterBar() {
    final clientName = _clientId != null
        ? (_clientOptions[_clientId] ?? 'Client')
        : null;
    final assigneeName = _assigneeId != null
        ? (_assigneeOptions[_assigneeId] ?? 'Assignee')
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChipBtn(
              icon: Icons.sort,
              label: _sortLabel,
              active: _sort != _Sort.newest,
              onTap: _showSortSheet,
            ),
            const SizedBox(width: 8),
            if (_profile?.isClient != true) ...[
              _FilterChipBtn(
                icon: Icons.business_outlined,
                label: clientName ?? S.t('all_clients'),
                active: _clientId != null,
                onTap: _showClientFilterSheet,
              ),
              const SizedBox(width: 8),
            ],
            if (_profile?.isClient != true) ...[
              _FilterChipBtn(
                icon: Icons.person_outline,
                label: assigneeName ?? S.t('all_assignees'),
                active: _assigneeId != null,
                onTap: _showAssigneeFilterSheet,
              ),
              const SizedBox(width: 8),
            ],
            if (_hasActiveFilters)
              _FilterChipBtn(
                icon: Icons.close,
                label: S.t('clear'),
                active: true,
                activeColor: AppColors.error,
                onTap: _clearFilters,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableView({Key? key}) {
    return SingleChildScrollView(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterBar(
            filters: _statusFilters,
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          if (_profile?.isAdmin == true) _buildSortFilterBar(),
          NotionTable(
            columns: _columns,
            rows: _buildRows(),
            onRowTap: (id) => _showDetailSheet(context, id),
            onAddRow: _perms?.canCreateTask == true
                ? () => _showCreateSheet(context)
                : null,
            onAddColumn: _perms?.canEditFull == true
                ? _showAddColumnDialog
                : null,
            onRowDelete: _perms?.canDeleteTask == true
                ? (id) => _deleteTaskRow(id)
                : null,
            onRowArchive: (_perms?.canEditFull == true ||
                    _profile?.isSuperAdmin == true ||
                    _profile?.isAdmin == true ||
                    _profile?.isManager == true)
                ? (id) => _archiveTaskRow(id)
                : null,
            isSelectionMode: _isSelectionMode,
            selectedRowIds: _selectedTaskIds,
            onRowSelect: (id, sel) {
              setState(() {
                if (sel) {
                  _selectedTaskIds.add(id);
                } else {
                  _selectedTaskIds.remove(id);
                }
              });
            },
            onSelectAll: (sel) {
              setState(() {
                if (sel) {
                  _selectedTaskIds = _filtered.map((t) => t.id).toSet();
                } else {
                  _selectedTaskIds.clear();
                }
              });
            },
            onRowReorder:
                (_perms?.canReorderTasks == true &&
                    _sort == _Sort.newest &&
                    _clientId == null &&
                    _assigneeId == null)
                ? (orderedIds) {
                    final reordered = <TaskModel>[];
                    for (final id in orderedIds) {
                      final match = _tasks.where((t) => t.id == id);
                      if (match.isNotEmpty) reordered.add(match.first);
                    }
                    setState(() => _tasks = reordered);
                  }
                : null,
            emptyMessage: _hasActiveFilters
                ? 'No tasks match these filters'
                : 'No tasks for ${_monthLabel(_activeMonth)}',
            emptyIcon: Icons.task_outlined,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _deleteTaskRow(String id) async {
    final ok = await TaskRepository.deleteTask(id);
    if (ok) {
      setState(() {
        _tasks.removeWhere((t) => t.id == id);
        _selectedTaskIds.remove(id);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task deleted')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete task')));
        _load();
      }
    }
  }

  Widget _buildBoardView({Key? key}) {
    final base = _filtered;
    final kanban = {
      'not_started': base.where((t) => t.status == 'not_started').toList(),
      'in_progress': base.where((t) => t.status == 'in_progress').toList(),
      'employee_done': base.where((t) => t.status == 'employee_done').toList(),
      'client_approved': base
          .where((t) => t.status == 'client_approved')
          .toList(),
      'client_rejected': base
          .where((t) => t.status == 'client_rejected')
          .toList(),
      'completed': base.where((t) => t.status == 'completed').toList(),
      'on_hold': base.where((t) => t.status == 'on_hold').toList(),
    };
    final columnDefs = [
      _KanbanDef(
        key: 'not_started',
        label: 'TO DO',
        color: AppColors.statusTodo,
      ),
      _KanbanDef(
        key: 'in_progress',
        label: 'IN PROGRESS',
        color: AppColors.statusInProgress,
      ),
      _KanbanDef(
        key: 'employee_done',
        label: 'EMPLOYEE DONE',
        color: AppColors.statusMedium,
      ),
      _KanbanDef(
        key: 'client_approved',
        label: 'CLIENT APPROVED',
        color: AppColors.statusDone,
      ),
      _KanbanDef(
        key: 'client_rejected',
        label: 'CLIENT REJECTED',
        color: AppColors.error,
      ),
      _KanbanDef(
        key: 'completed',
        label: 'COMPLETED',
        color: AppColors.statusDone,
      ),
      _KanbanDef(key: 'on_hold', label: 'ON HOLD', color: AppColors.outline),
    ];
    return Column(
      key: key,
      children: [
        _FilterBar(
          filters: _statusFilters,
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
        if (_profile?.isAdmin == true) _buildSortFilterBar(),
        Expanded(
          child: Scrollbar(
            controller: _boardHorizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            child: ListView.builder(
              controller: _boardHorizontalController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              // ignore: deprecated_member_use
              cacheExtent: 600.0,
              addRepaintBoundaries: true,
              itemCount: columnDefs.length,
              itemBuilder: (context, index) {
                final col = columnDefs[index];
                final tasks = kanban[col.key] ?? [];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _KanbanColumn(
                    title: col.label,
                    color: col.color,
                    tasks: tasks,
                    showCost: _perms?.canSeeCost == true,
                    showProgress: _perms?.canSeeProgress != false,
                    isSelectionMode: _isSelectionMode,
                    selectedTaskIds: _selectedTaskIds,
                    onTaskSelect: (id, sel) {
                      setState(() {
                        if (sel) {
                          _selectedTaskIds.add(id);
                        } else {
                          _selectedTaskIds.remove(id);
                        }
                      });
                    },
                    onTaskTap: (id) => _showDetailSheet(context, id),
                    onTaskDelete: _perms?.canDeleteTask == true
                        ? (id) => _deleteTaskRow(id)
                        : null,
                    onTaskArchive: (_perms?.canEditFull == true ||
                            _profile?.isSuperAdmin == true ||
                            _profile?.isAdmin == true ||
                            _profile?.isManager == true)
                        ? (id) => _archiveTaskRow(id)
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddColumnDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Column'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Column name',
            prefixIcon: Icon(Icons.view_column_outlined, color: AppColors.gold),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              setState(() {
                _customColumns.add(
                  NotionColumn(
                    key: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    label: ctrl.text.trim(),
                    icon: Icons.label_outline,
                    removable: true,
                  ),
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateTaskSheet(
        initialMonth: _activeMonth,
        isLiveMonth: _activeMonth == _liveMonth,
        onCreated: () {
          Navigator.pop(context);
          _load(animate: false);
        },
      ),
    );
  }

  void _showDetailSheet(BuildContext context, String id) {
    final matches = _tasks.where((t) => t.id == id);
    final task = matches.isEmpty ? null : matches.first;
    final canMove =
        task != null &&
        task.handoffToTeamId == null &&
        (_profile?.isAdmin == true ||
            _profile?.isSuperAdmin == true ||
            _profile?.isManager == true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TaskDetailSheet(
        taskId: id,
        onUpdated: () => _load(animate: false),
        onMoveDepartment: canMove ? () => _moveToDepartment(task) : null,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// Supporting Private Sub-Widgets
// ════════════════════════════════════════════════════════════════════════════════

class _KanbanDef {
  final String key;
  final String label;
  final Color color;
  const _KanbanDef({
    required this.key,
    required this.label,
    required this.color,
  });
}

class _ProgressCell extends StatelessWidget {
  final int pct;
  const _ProgressCell({required this.pct});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            width: isMobile ? 24 : 36,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: isMobile ? 3 : 4,
                backgroundColor: AppColors.outlineVariant,
                color: AppColors.gold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$pct%',
          style: AppTextStyles.dataSm.copyWith(fontSize: isMobile ? 9 : 10),
        ),
      ],
    );
  }
}

class _CommentsCountBadge extends StatelessWidget {
  final int count;
  const _CommentsCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return Text('—', style: AppTextStyles.bodySm);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.comment_outlined,
          size: 13,
          color: AppColors.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text('$count', style: AppTextStyles.dataSm),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(S.t(f)),
                    selected: selected == f,
                    onSelected: (_) => onSelected(f),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceContainerLowest,
                    labelStyle: AppTextStyles.bodySm.copyWith(
                      color: selected == f ? Colors.white : AppColors.onSurface,
                      fontWeight: selected == f
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: selected == f
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  const _FilterChipBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : AppColors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? color : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.bodySm.copyWith(
                color: active ? color : AppColors.onSurface,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: active ? color : AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPill extends StatelessWidget {
  const _MonthPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.isLive = false,
  });
  final String label;
  final bool active;
  final bool isLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: active ? 16 : 12,
          vertical: active ? 9 : 7,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  isLive ? Icons.today : Icons.calendar_month,
                  size: 15,
                  color: AppColors.gold,
                ),
              ),
            Text(
              label,
              style: AppTextStyles.bodySm.copyWith(
                color: active ? Colors.white : AppColors.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: active ? 13 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.title,
    required this.color,
    required this.tasks,
    required this.showCost,
    required this.showProgress,
    this.isSelectionMode = false,
    this.selectedTaskIds,
    this.onTaskSelect,
    this.onTaskTap,
    this.onTaskDelete,
    this.onTaskArchive,
  });

  final String title;
  final Color color;
  final List<TaskModel> tasks;
  final bool showCost;
  final bool showProgress;
  final bool isSelectionMode;
  final Set<String>? selectedTaskIds;
  final void Function(String id, bool selected)? onTaskSelect;
  final ValueChanged<String>? onTaskTap;
  final ValueChanged<String>? onTaskDelete;
  final ValueChanged<String>? onTaskArchive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelCaps.copyWith(color: color),
                ),
                const Spacer(),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${tasks.length}',
                      style: AppTextStyles.bodySm.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: tasks.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No tasks',
                        style: AppTextStyles.bodySm.copyWith(
                          color:
                              AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    // ignore: deprecated_member_use
                    cacheExtent: 400.0,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: true,
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(task.id),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 200 + index * 40),
                        curve: Curves.easeOut,
                        builder: (_, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - v)),
                            child: child,
                          ),
                        ),
                        child: _KanbanCard(
                          task: task,
                          showCost: showCost,
                          showProgress: showProgress,
                          isSelectionMode: isSelectionMode,
                          isSelected: selectedTaskIds?.contains(task.id) ?? false,
                          onSelectToggle: () {
                            final curr = selectedTaskIds?.contains(task.id) ?? false;
                            onTaskSelect?.call(task.id, !curr);
                          },
                          onTap: onTaskTap != null
                              ? () => onTaskTap!(task.id)
                              : null,
                          onDelete: onTaskDelete != null
                              ? () => onTaskDelete!(task.id)
                              : null,
                          onArchive: onTaskArchive != null
                              ? () => onTaskArchive!(task.id)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.task,
    required this.showCost,
    required this.showProgress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectToggle,
    this.onTap,
    this.onDelete,
    this.onArchive,
  });

  final TaskModel task;
  final bool showCost;
  final bool showProgress;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onArchive;

  Future<bool> _confirmCardArchive(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Task'),
        content: const Text('Are you sure you want to archive this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmCardDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dir = (onDelete != null && onArchive != null)
        ? DismissDirection.horizontal
        : (onArchive != null
            ? DismissDirection.startToEnd
            : (onDelete != null ? DismissDirection.endToStart : DismissDirection.none));

    Widget cardContent = RepaintBoundary(
      child: GestureDetector(
        onTap: isSelectionMode ? onSelectToggle : onTap,
        child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.gold.withValues(alpha: 0.12)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSelectionMode) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: AppColors.gold,
                      checkColor: Colors.black,
                      onChanged: (_) => onSelectToggle?.call(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                TPriorityBadge(priority: task.priorityLabel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.title,
              style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            if (showProgress && task.completionPercentage > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: task.completionPercentage / 100,
                  minHeight: 4,
                  backgroundColor: AppColors.outlineVariant,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${task.completionPercentage}%',
                  style: AppTextStyles.dataSm,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                if (task.assignees.isNotEmpty)
                  TAvatar(name: task.leadAssigneeName, size: 24),
                const Spacer(),
                if (showCost && task.cost != null) ...[
                  const Icon(
                    Icons.monetization_on_outlined,
                    size: 12,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'EGP ${task.cost!.toStringAsFixed(0)}',
                    style: AppTextStyles.dataSm.copyWith(color: AppColors.gold),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(task.dueDateDisplay, style: AppTextStyles.bodySm),
              ],
            ),
          ],
        ),
      ),
    ),
  );

    if (dir != DismissDirection.none) {
      cardContent = Dismissible(
        key: ValueKey('kanban_${task.id}'),
        direction: dir,
        background: Container(
          margin: const EdgeInsets.only(bottom: 10),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.archive_outlined, color: AppColors.gold, size: 20),
              const SizedBox(width: 6),
              Text(
                'Archive',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.gold, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.only(bottom: 10),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
              const SizedBox(width: 6),
              Text(
                'Delete',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            return await _confirmCardArchive(context);
          } else if (direction == DismissDirection.endToStart) {
            return await _confirmCardDelete(context);
          }
          return false;
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.startToEnd) {
            onArchive?.call();
          } else if (direction == DismissDirection.endToStart) {
            onDelete?.call();
          }
        },
        child: cardContent,
      );
    }

    return cardContent;
  }
}

class _CreateTaskSheet extends StatefulWidget {
  final VoidCallback onCreated;
  // The month workspace the user is currently viewing. A new task defaults its
  // due date so it lands in this month. [isLiveMonth] is true when that is the
  // real current calendar month.
  final DateTime initialMonth;
  final bool isLiveMonth;
  const _CreateTaskSheet({
    required this.onCreated,
    required this.initialMonth,
    required this.isLiveMonth,
  });

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  bool _commentIsInternal = true;
  String _priority = 'medium';
  String _status = 'not_started';
  DateTime? _dueDate;
  double _progress = 0.0;
  bool _creating = false;

  List<TaskStatusOption> _statusOptions = [];

  String? _selectedTeamId;
  List<TeamModel> _teams = [];

  String? _clientId;
  List<ClientModel> _clients = [];

  List<ProfileModel> _allEmployees = [];
  List<String> _selectedAssigneeIds = [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    // Default the due date so the new task belongs to the viewed month. For the
    // live current month we leave it null (creation date already anchors it
    // there, preserving prior behaviour); for a past/future workspace we seed
    // the month's first day so the task appears in that month. The user can
    // still change or clear it explicitly.
    if (!widget.isLiveMonth) {
      _dueDate = DateTime(
        widget.initialMonth.year,
        widget.initialMonth.month,
        1,
      );
    }
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final profile = context.read<AuthNotifier>().profile;

    // Clients (admin/manager create tasks with a client attached)
    ClientRepository.fetchClients().then((clients) {
      if (mounted) setState(() => _clients = clients);
    });

    // Status options — admin bootstraps on first run; all roles fetch.
    () async {
      if (profile?.isAdmin == true) {
        await TaskStatusOptionsRepository.init(profile!.id);
      }
      final opts = await TaskStatusOptionsRepository.fetchOptions();
      if (mounted) setState(() => _statusOptions = opts);
    }();

    if (profile?.isAdmin == true) {
      final teams = await TeamRepository.fetchAllAdmin(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _teams = teams;
        if (teams.isNotEmpty) _selectedTeamId = teams.first.id;
      });
    } else {
      _selectedTeamId = profile?.teamId;
    }
    await _loadMembers(_selectedTeamId);
  }

  Future<void> _loadMembers(String? teamId) async {
    if (teamId == null) {
      setState(() {
        _allEmployees = [];
        _selectedAssigneeIds = [];
      });
      return;
    }
    setState(() => _loadingMembers = true);
    try {
      final currentProfile = context.read<AuthNotifier>().profile;
      final members = await TeamRepository.fetchMembersAdmin(teamId);
      members.removeWhere((e) => e.isClient);
      if (currentProfile != null &&
          !currentProfile.isClient &&
          !members.any((e) => e.id == currentProfile.id)) {
        members.insert(0, currentProfile);
      }
      if (!mounted) return;
      setState(() {
        _allEmployees = members;
        // Drop any selected assignees no longer in the new team
        _selectedAssigneeIds.removeWhere(
          (id) => !members.any((e) => e.id == id),
        );
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _onTeamChanged(String? val) {
    setState(() => _selectedTeamId = val);
    _loadMembers(val);
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _creating = true);
    final profile = context.read<AuthNotifier>().profile!;
    final taskId = await TaskRepository.createTask(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      createdBy: profile.id,
      teamId: _selectedTeamId,
      clientId: _clientId,
      priority: _priority,
      status: _status,
      dueDate: _dueDate?.toIso8601String().split('T').first,
      cost: double.tryParse(_costCtrl.text.trim()),
      completionPercentage: _progress.round(),
    );

    if (taskId != null && _selectedAssigneeIds.isNotEmpty) {
      try {
        await TaskRepository.assignEmployees(
          taskId: taskId,
          profileIds: _selectedAssigneeIds,
          assignedBy: profile.id,
        );
      } catch (_) {}
    }

    // Post initial comment (may embed a link) once the task exists.
    final commentText = _commentCtrl.text.trim();
    if (taskId != null && commentText.isNotEmpty) {
      try {
        await TaskRepository.addComment(
          taskId,
          profile.id,
          commentText,
          isInternal: _commentIsInternal,
        );
      } catch (_) {}
    }

    widget.onCreated();
  }

  Future<void> _showStatusOptionsManager() async {
    final profile = context.read<AuthNotifier>().profile;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatusOptionsManagerSheet(
        isAdmin: profile?.isAdmin ?? false,
        adminUserId: profile?.id,
        onChanged: () async {
          final opts = await TaskStatusOptionsRepository.fetchOptions();
          if (mounted) setState(() => _statusOptions = opts);
        },
      ),
    );
  }

  void _showInsertLinkDialog() {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.link, color: AppColors.gold),
            const SizedBox(width: 8),
            Text('Insert Link into Comment', style: AppTextStyles.headlineSm),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Link URL *',
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.http, color: AppColors.gold),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Link Label (Optional)',
                hintText: 'e.g. Project Specs',
                prefixIcon: Icon(Icons.label_outline, color: AppColors.gold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                final label = labelCtrl.text.trim();
                final formatted = label.isNotEmpty ? '[$label]($url)' : url;
                setState(() {
                  if (_commentCtrl.text.isNotEmpty) {
                    _commentCtrl.text = '${_commentCtrl.text} $formatted';
                  } else {
                    _commentCtrl.text = formatted;
                  }
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Insert Link'),
          ),
        ],
      ),
    );
  }

  void _showAssigneePicker() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          title: const Text('Select Assignees'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _allEmployees.isEmpty
                ? Center(
                    child: Text(
                      'No team members to assign',
                      style: AppTextStyles.bodySm,
                    ),
                  )
                : ListView.builder(
                    itemCount: _allEmployees.length,
                    itemBuilder: (_, idx) {
                      final emp = _allEmployees[idx];
                      final sel = _selectedAssigneeIds.contains(emp.id);
                      return CheckboxListTile(
                        value: sel,
                        activeColor: AppColors.gold,
                        title: Row(
                          children: [
                            TAvatar(name: emp.fullName, size: 24),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                emp.fullName,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMd,
                              ),
                            ),
                          ],
                        ),
                        onChanged: (v) {
                          setDialog(() {
                            if (v == true) {
                              _selectedAssigneeIds.add(emp.id);
                            } else {
                              _selectedAssigneeIds.remove(emp.id);
                            }
                          });
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _costCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('New Task', style: AppTextStyles.headlineSm),
            const SizedBox(height: 4),
            Text('Fill in the details below', style: AppTextStyles.bodySm),
            const Divider(height: 24),

            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'TITLE',
                hintText: 'Enter task title',
                prefixIcon: Icon(Icons.title, color: AppColors.gold, size: 18),
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'DESCRIPTION',
                hintText: 'Optional description…',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 36),
                  child: Icon(Icons.notes, color: AppColors.gold, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 18),

            if (context.read<AuthNotifier>().profile?.isAdmin == true &&
                _teams.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('DEPARTMENT', style: AppTextStyles.labelCaps),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _selectedTeamId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Select department/team',
                  prefixIcon: const Icon(
                    Icons.group_outlined,
                    color: AppColors.gold,
                    size: 18,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: _teams
                    .map(
                      (t) => DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _onTeamChanged,
              ),
              const SizedBox(height: 18),
            ],

            // Client
            Align(
              alignment: Alignment.centerLeft,
              child: Text('CLIENT', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            if (_clients.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No clients — create one in the Clients section.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              DropdownButtonFormField<String?>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'No client attached',
                  prefixIcon: const Icon(
                    Icons.business_outlined,
                    color: AppColors.gold,
                    size: 18,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— No client —'),
                  ),
                  ..._clients.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(
                        c.companyName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _clientId = val),
              ),
            const SizedBox(height: 18),

            Align(
              alignment: Alignment.centerLeft,
              child: Text('PRIORITY', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildPriorityChip('low', 'Low', AppColors.statusLow),
                _buildPriorityChip('medium', 'Medium', AppColors.statusMedium),
                _buildPriorityChip('high', 'High', AppColors.statusHigh),
                _buildPriorityChip('critical', 'Critical', AppColors.error),
              ],
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Text('STATUS', style: AppTextStyles.labelCaps),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.tune, size: 14, color: AppColors.gold),
                  label: Text(
                    context.read<AuthNotifier>().profile?.isAdmin == true
                        ? 'Edit Options'
                        : 'View Options',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.gold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: _showStatusOptionsManager,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _statusOptions
                  .map((opt) => _buildStatusChip(opt.label, opt.displayLabel))
                  .toList(),
            ),
            const SizedBox(height: 18),

            // Progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PROGRESS', style: AppTextStyles.labelCaps),
                Text(
                  '${_progress.round()}%',
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Slider(
              value: _progress,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: AppColors.gold,
              inactiveColor: AppColors.outlineVariant,
              onChanged: (v) => setState(() => _progress = v),
            ),
            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerLeft,
              child: Text('DUE DATE', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final today = DateTime.now();
                final monthStart = DateTime(
                  widget.initialMonth.year,
                  widget.initialMonth.month,
                  1,
                );
                final monthEnd = DateTime(
                  widget.initialMonth.year,
                  widget.initialMonth.month + 1,
                  0,
                );
                // Allow the whole viewed month even if it is in the past/future.
                final firstDate = monthStart.isBefore(today) ? monthStart : today;
                final lastDate =
                    monthEnd.isAfter(today.add(const Duration(days: 365)))
                    ? monthEnd
                    : today.add(const Duration(days: 365));
                var initial =
                    _dueDate ?? today.add(const Duration(days: 7));
                if (initial.isBefore(firstDate)) initial = firstDate;
                if (initial.isAfter(lastDate)) initial = lastDate;
                final d = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: firstDate,
                  lastDate: lastDate,
                );
                if (d != null) setState(() => _dueDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _dueDate != null
                          ? '${_dueDate!.year}-'
                                '${_dueDate!.month.toString().padLeft(2, '0')}-'
                                '${_dueDate!.day.toString().padLeft(2, '0')}'
                          : 'Select date…',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: _dueDate != null
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Cost
            TextField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'COST',
                hintText: 'e.g. 1500.00',
                prefixIcon: Icon(
                  Icons.monetization_on_outlined,
                  color: AppColors.gold,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Assignees
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ASSIGNEES', style: AppTextStyles.labelCaps),
                if (_loadingMembers)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.gold,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: AppColors.gold,
                    ),
                    onPressed: _showAssigneePicker,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (_selectedAssigneeIds.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('No assignees', style: AppTextStyles.bodySm),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedAssigneeIds.map((uid) {
                  final emp = _allEmployees.firstWhere(
                    (e) => e.id == uid,
                    orElse: () => ProfileModel(
                      id: uid,
                      role: 'employee',
                      fullName: 'Unknown',
                      status: 'active',
                      timezone: 'UTC',
                      preferredLanguage: 'en',
                      createdAt: '',
                    ),
                  );
                  return Chip(
                    avatar: TAvatar(name: emp.fullName, size: 18),
                    label: Text(emp.fullName.split(' ').first),
                    onDeleted: () =>
                        setState(() => _selectedAssigneeIds.remove(uid)),
                    deleteIcon: const Icon(Icons.cancel, size: 16),
                  );
                }).toList(),
              ),
            const SizedBox(height: 18),

            // Initial comment (optional) — supports link insert + internal/public
            Align(
              alignment: Alignment.centerLeft,
              child: Text('COMMENT', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Add an initial comment… (optional)',
                      hintStyle: AppTextStyles.bodySm,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.link, color: AppColors.gold, size: 20),
                      tooltip: 'Insert Link into Comment',
                      onPressed: _showInsertLinkDialog,
                    ),
                    IconButton(
                      icon: Icon(
                        _commentIsInternal ? Icons.lock_outline : Icons.public,
                        color: _commentIsInternal
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        size: 18,
                      ),
                      tooltip: _commentIsInternal
                          ? 'Internal comment'
                          : 'Visible to client',
                      onPressed: () => setState(
                        () => _commentIsInternal = !_commentIsInternal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _creating ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _creating ? null : _create,
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.gold,
                            ),
                          )
                        : const Text('Create Task'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildPriorityChip(String key, String label, Color color) {
    final sel = _priority == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _priority = key),
      selectedColor: color.withValues(alpha: 0.18),
      backgroundColor: AppColors.surfaceContainerLowest,
      labelStyle: AppTextStyles.bodySm.copyWith(
        color: sel ? color : AppColors.onSurface,
        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: sel ? color : AppColors.outlineVariant),
      ),
    );
  }

  Widget _buildStatusChip(String key, String label) {
    final sel = _status == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _status = key),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLowest,
      labelStyle: AppTextStyles.bodySm.copyWith(
        color: sel ? Colors.white : AppColors.onSurface,
        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: sel ? AppColors.primary : AppColors.outlineVariant,
        ),
      ),
    );
  }
}

class _WaitingList extends StatelessWidget {
  const _WaitingList({
    required this.tasks,
    required this.teamName,
    required this.onAccept,
    required this.onReject,
    required this.onView,
  });
  final List<TaskModel> tasks;
  final String Function(String?) teamName;
  final Future<void> Function(TaskModel) onAccept;
  final Future<void> Function(TaskModel) onReject;
  final void Function(TaskModel) onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inbox_outlined, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Text('Waiting List', style: AppTextStyles.labelMd),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tasks.length}',
                  style: AppTextStyles.bodySm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tasks handed to your department. Accept to assign your team or reject to return.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          ...tasks.map(
            (t) => InkWell(
              onTap: () => onView(t),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: AppTextStyles.labelMd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'From: ${teamName(t.handoffFromTeamId)}',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tap to view',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => onAccept(t),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusDone,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Accept',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => onReject(t),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Reject',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
