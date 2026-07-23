// lib/features/tasks/task_board_screen.dart
// Role-aware task board: table view + kanban view.
// Column set and available actions adapt to admin / manager / employee / client.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/models/task_model.dart';
import '../../core/models/team_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/utils/task_permissions.dart';
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
    with TickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';
  _Sort _sort = _Sort.newest;
  String? _clientId; // null = all clients
  String? _assigneeId; // null = all assignees
  bool _isTableView = true;

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
  }

  @override
  void didUpdateWidget(TaskBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != null &&
        widget.initialFilter != oldWidget.initialFilter &&
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
        return 'Newest first';
      case _Sort.oldest:
        return 'Oldest first';
      case _Sort.dueDate:
        return 'Due date';
      case _Sort.priorityHigh:
        return 'Priority (high→low)';
      case _Sort.clientAZ:
        return 'Client A–Z';
      case _Sort.titleAZ:
        return 'Title A–Z';
      case _Sort.moved:
        return 'Moved tasks';
    }
  }

  bool get _hasActiveFilters =>
      _filter != 'All' ||
      _clientId != null ||
      _assigneeId != null ||
      _sort != _Sort.newest;

  // ── Role-based columns ────────────────────────────────────────────────────

  List<NotionColumn> get _columns {
    final p = _perms;
    return [
      NotionColumn(
        key: 'title',
        label: 'Task',
        icon: Icons.text_fields,
        flex: 3,
      ),
      NotionColumn(
        key: 'status',
        label: 'Status',
        icon: Icons.circle_outlined,
        flex: 2,
      ),
      if (p?.canSeePriority != false)
        NotionColumn(
          key: 'priority',
          label: 'Priority',
          icon: Icons.flag_outlined,
          flex: 2,
        ),
      if (p?.canSeeAssignees != false)
        NotionColumn(
          key: 'assignee',
          label: 'Assignee',
          icon: Icons.person_outline,
          flex: 2,
        ),
      NotionColumn(
        key: 'due',
        label: 'Due',
        icon: Icons.calendar_today_outlined,
        flex: 2,
      ),
      if (p?.canSeeProgress != false)
        NotionColumn(
          key: 'progress',
          label: 'Progress',
          icon: Icons.trending_up,
          flex: 2,
        ),
      if (p?.canSeeCost == true)
        NotionColumn(
          key: 'cost',
          label: 'Cost / Price',
          icon: Icons.monetization_on_outlined,
          flex: 2,
        ),
      if (p?.canSeeComments == true)
        NotionColumn(
          key: 'comments',
          label: 'Comments',
          icon: Icons.comment_outlined,
          flex: 1,
        ),
      ..._customColumns,
    ];
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool animate = true}) async {
    if (animate)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final profile = context.read<AuthNotifier>().profile;
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
      if (mounted)
        setState(() {
          _tasks = data as List<TaskModel>;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
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
        // FittedBox prevents the chip overflowing (and overlapping the next
        // column) when the cell is narrow on a phone.
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

  // ── Sort / filter dialogs ─────────────────────────────────────────────────

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
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
    );
  }

  void _showClientFilterSheet() {
    final opts = _clientOptions;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
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
    );
  }

  void _showAssigneeFilterSheet() {
    final opts = _assigneeOptions;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
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
    );
  }

  void _clearFilters() {
    setState(() {
      _filter = 'All';
      _clientId = null;
      _assigneeId = null;
      _sort = _Sort.newest;
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _isTableView ? 'Tasks — Table' : 'Tasks — Board',
            key: ValueKey(_isTableView),
          ),
        ),
        actions: [
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
      ),
      // Hide FAB for clients — they cannot create tasks
      floatingActionButton: (_perms?.canCreateTask != false)
          ? FloatingActionButton(
              onPressed: () => _showCreateSheet(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: AppColors.gold),
            )
          : null,
      body: Column(
        children: [
          const TeamFilterChip(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    if (_error != null) {
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
    final canManage = _profile?.isAdmin == true || _profile?.isManager == true;
    final waiting = _waiting;
    return Column(
      children: [
        if (canManage && waiting.isNotEmpty)
          _WaitingList(
            tasks: waiting,
            teamName: _teamName,
            onAccept: _acceptHandoff,
            onView: _openWaitingDetail,
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            // Align children to the top — default centers a short child and
            // leaves a big empty gap above the table.
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

  String _teamName(String? teamId) {
    if (teamId == null) return '—';
    final t = _teams.where((t) => t.id == teamId);
    return t.isEmpty ? 'Other dept' : t.first.name;
  }

  /// Open a waiting-list task's full details, with an Accept action inside.
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

  /// Move a task to another department. Source = task's current team (admins
  /// can move any task; managers only their own team's tasks).
  Future<void> _moveToDepartment(TaskModel task) async {
    final sourceTeam = task.teamId ?? _profile?.teamId;
    // Candidate targets: teams of a different department.
    String? myDept;
    for (final t in _teams) {
      if (t.id == sourceTeam) {
        myDept = t.department;
        break;
      }
    }
    final targets = _teams
        .where(
          (t) =>
              t.id != sourceTeam && (myDept == null || t.department != myDept),
        )
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other department to hand off to.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<TeamModel>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Move to department', style: AppTextStyles.headlineSm),
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
            // Sort chip
            _FilterChipBtn(
              icon: Icons.sort,
              label: _sortLabel,
              active: _sort != _Sort.newest,
              onTap: _showSortSheet,
            ),
            const SizedBox(width: 8),
            // Client filter (not shown to client role — they always see their own)
            if (_profile?.isClient != true) ...[
              _FilterChipBtn(
                icon: Icons.business_outlined,
                label: clientName ?? 'All clients',
                active: _clientId != null,
                onTap: _showClientFilterSheet,
              ),
              const SizedBox(width: 8),
            ],
            // Assignee filter
            if (_profile?.isClient != true) ...[
              _FilterChipBtn(
                icon: Icons.person_outline,
                label: assigneeName ?? 'All assignees',
                active: _assigneeId != null,
                onTap: _showAssigneeFilterSheet,
              ),
              const SizedBox(width: 8),
            ],
            // Clear all filters
            if (_hasActiveFilters)
              _FilterChipBtn(
                icon: Icons.close,
                label: 'Clear',
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
          // Sort / client / assignee filters are only useful for the admin's
          // full view — hide for manager/employee to keep tasks near the top.
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
                : 'No tasks yet',
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
      setState(() => _tasks.removeWhere((t) => t.id == id));
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
    // Apply client + assignee filters; status split is done per column below.
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
        if (_profile?.isAdmin == true) _buildSortFilterBar(),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            children: columnDefs.map((col) {
              final tasks = kanban[col.key] ?? [];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _KanbanColumn(
                  title: col.label,
                  color: col.color,
                  tasks: tasks,
                  showCost: _perms?.canSeeCost == true,
                  showProgress: _perms?.canSeeProgress != false,
                  onTaskTap: (id) => _showDetailSheet(context, id),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAddColumnDialog() {
    final ctrl = TextEditingController();
    showDialog(
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
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateTaskSheet(
        onCreated: () {
          Navigator.pop(context);
          _load(animate: false);
        },
      ),
    );
  }

  void _showDetailSheet(BuildContext context, String id) {
    // Allow department handoff only for a manager on their own active team task.
    final matches = _tasks.where((t) => t.id == id);
    final task = matches.isEmpty ? null : matches.first;
    final canMove =
        task != null &&
        task.teamId != null &&
        task.handoffToTeamId == null &&
        (_profile?.isAdmin == true ||
            (_profile?.isManager == true && task.teamId == _profile?.teamId));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
// Supporting widgets
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
                    label: Text(f),
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

// ── Sort/filter chip button ───────────────────────────────────────────────────

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

// ── Kanban Column ─────────────────────────────────────────────────────────────

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.title,
    required this.color,
    required this.tasks,
    required this.showCost,
    required this.showProgress,
    this.onTaskTap,
  });

  final String title;
  final Color color;
  final List<TaskModel> tasks;
  final bool showCost;
  final bool showProgress;
  final ValueChanged<String>? onTaskTap;

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
          ...tasks.asMap().entries.map(
            (e) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + e.key * 80),
              curve: Curves.easeOut,
              builder: (_, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - v)),
                  child: child,
                ),
              ),
              child: _KanbanCard(
                task: e.value,
                showCost: showCost,
                showProgress: showProgress,
                onTap: onTaskTap != null ? () => onTaskTap!(e.value.id) : null,
              ),
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
    this.onTap,
  });

  final TaskModel task;
  final bool showCost;
  final bool showProgress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
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
            TPriorityBadge(priority: task.priorityLabel),
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
    );
  }
}

// ── Create Task Bottom Sheet ──────────────────────────────────────────────────

class _CreateTaskSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateTaskSheet({required this.onCreated});

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';
  String _status = 'not_started';
  DateTime? _dueDate;
  bool _creating = false;

  String? _selectedTeamId;
  List<TeamModel> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile?.isAdmin == true) {
      final teams = await TeamRepository.fetchAllAdmin(activeOnly: true);
      setState(() {
        _teams = teams;
        if (teams.isNotEmpty) {
          _selectedTeamId = teams.first.id;
        }
      });
    } else {
      _selectedTeamId = profile?.teamId;
    }
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _creating = true);
    final profile = context.read<AuthNotifier>().profile!;
    await TaskRepository.createTask(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      createdBy: profile.id,
      teamId: _selectedTeamId,
      priority: _priority,
      dueDate: _dueDate?.toIso8601String().split('T').first,
    );
    widget.onCreated();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
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

            // Department (only for Admin)
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
                onChanged: (val) => setState(() => _selectedTeamId = val),
              ),
              const SizedBox(height: 18),
            ],

            // Priority
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

            // Status
            Align(
              alignment: Alignment.centerLeft,
              child: Text('STATUS', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildStatusChip('not_started', 'To Do'),
                _buildStatusChip('in_progress', 'In Progress'),
                _buildStatusChip('employee_done', 'Employee Done'),
                _buildStatusChip('on_hold', 'On Hold'),
              ],
            ),
            const SizedBox(height: 18),

            // Due date
            Align(
              alignment: Alignment.centerLeft,
              child: Text('DUE DATE', style: AppTextStyles.labelCaps),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate:
                      _dueDate ?? DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
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

// ── Waiting List (department handoff inbox) ───────────────────────────────────
class _WaitingList extends StatelessWidget {
  const _WaitingList({
    required this.tasks,
    required this.teamName,
    required this.onAccept,
    required this.onView,
  });
  final List<TaskModel> tasks;
  final String Function(String?) teamName;
  final Future<void> Function(TaskModel) onAccept;
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
            'Tasks handed to your department. Accept to assign your team.',
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
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => onAccept(t),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusDone,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
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
