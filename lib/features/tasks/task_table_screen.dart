// lib/features/tasks/task_table_screen.dart
// Role-aware Notion-style database table.
// Shown columns and available actions depend on admin / manager / employee / client.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/models/task_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/utils/task_permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/notion_table.dart';
import 'task_detail_sheet.dart';

class TaskTableScreen extends StatefulWidget {
  const TaskTableScreen({super.key});
  @override
  State<TaskTableScreen> createState() => _TaskTableScreenState();
}

class _TaskTableScreenState extends State<TaskTableScreen>
    with SingleTickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';

  ProfileModel? _profile;
  TaskPermissions? _perms;

  late AnimationController _pageAnim;
  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;

  static const _statusFilters = [
    'All', 'To Do', 'In Progress', 'Employee Done',
    'Client Approved', 'Client Rejected', 'Completed', 'On Hold',
  ];
  static const _statusMap = <String, String>{
    'To Do':            'not_started',
    'In Progress':      'in_progress',
    'Employee Done':    'employee_done',
    'Client Approved':  'client_approve',
    'Client Rejected':  'client_rejected',
    'Completed':        'completed',
    'On Hold':          'on_hold',
  };

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pageFade = CurvedAnimation(
        parent: _pageAnim, curve: Curves.easeOut);
    _pageSlide = Tween<Offset>(
      begin: const Offset(0, 0.03), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pageAnim, curve: Curves.easeOut));
    _load();
  }

  @override
  void dispose() {
    _pageAnim.dispose();
    super.dispose();
  }

  List<TaskModel> get _filtered {
    if (_filter == 'All') return _tasks;
    final key = _statusMap[_filter] ?? '';
    return _tasks.where((t) => t.status == key).toList();
  }

  // ── Role-based columns ────────────────────────────────────────────────────

  List<NotionColumn> get _columns {
    final p = _perms;
    return [
      NotionColumn(key: 'title', label: 'Task',
          icon: Icons.text_fields, flex: 3),
      NotionColumn(key: 'status', label: 'Status',
          icon: Icons.circle_outlined, flex: 2),
      if (p?.canSeePriority != false)
        NotionColumn(key: 'priority', label: 'Priority',
            icon: Icons.flag_outlined, flex: 2),
      if (p?.canSeeAssignees != false)
        NotionColumn(key: 'assignee', label: 'Assignee',
            icon: Icons.person_outline, flex: 2),
      NotionColumn(key: 'due', label: 'Due',
          icon: Icons.calendar_today_outlined, flex: 2),
      if (p?.canSeeProgress != false)
        NotionColumn(key: 'progress', label: 'Progress',
            icon: Icons.trending_up, flex: 2),
      if (p?.canSeeCost == true)
        NotionColumn(key: 'cost', label: 'Cost / Price',
            icon: Icons.monetization_on_outlined, flex: 2),
      if (p?.canSeeComments == true)
        NotionColumn(key: 'comments', label: 'Comments',
            icon: Icons.comment_outlined, flex: 1),
      if (p?.canSeeEditHistory == true)
        NotionColumn(key: 'edited', label: 'Last Edited',
            icon: Icons.edit_outlined, flex: 2),
    ];
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool animate = true}) async {
    if (animate) setState(() { _loading = true; _error = null; });
    try {
      final profile = context.read<AuthNotifier>().profile;
      _profile = profile;
      _perms   = profile != null ? TaskPermissions(profile) : null;

      final data = profile != null
          ? await TaskRepository.fetchTasksForProfile(profile)
          : <TaskModel>[];
      if (mounted) {
        setState(() { _tasks = data; _loading = false; });
        if (animate) _pageAnim.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
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
        'title': Text(t.title,
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        'status': TStatusChip(
            label: t.statusLabel,
            color: _statusColor(t.status)),
        if (_perms?.canSeePriority != false)
          'priority': TPriorityBadge(priority: t.priorityLabel),
        if (_perms?.canSeeAssignees != false)
          'assignee': Row(mainAxisSize: MainAxisSize.min, children: [
            TAvatar(name: t.leadAssigneeName, size: avatarSize),
            SizedBox(width: isMobile ? 3 : 5),
            Flexible(
              child: Text(t.leadAssigneeName,
                  style: bodyStyle,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        'due': Text(t.dueDateDisplay, style: dataStyle),
        if (_perms?.canSeeProgress != false)
          'progress': Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: isMobile ? 24 : 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: t.completionPercentage / 100,
                  minHeight: isMobile ? 3 : 4,
                  backgroundColor: AppColors.outlineVariant,
                  color: AppColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('${t.completionPercentage}%',
                style: dataStyle.copyWith(fontSize: isMobile ? 9 : 10)),
          ]),
        if (_perms?.canSeeCost == true)
          'cost': Text(
            t.cost != null
                ? '\$${t.cost!.toStringAsFixed(2)}'
                : '—',
            style: dataStyle.copyWith(color: AppColors.gold),
          ),
        if (_perms?.canSeeComments == true)
          'comments': _CommentsCountBadge(count: t.comments.length),
        if (_perms?.canSeeEditHistory == true)
          'edited': Text(
            t.editLogs.isNotEmpty
                ? t.editLogs.first.editorName
                : '—',
            style: dataStyle,
            overflow: TextOverflow.ellipsis,
          ),
      };
      return NotionRow(id: t.id, cells: cells);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':     return AppColors.statusInProgress;
      case 'employee_done':   return AppColors.statusMedium;
      case 'client_approve':  return AppColors.statusDone;
      case 'client_rejected': return AppColors.error;
      case 'completed':       return AppColors.statusDone;
      case 'on_hold':         return AppColors.outline;
      default:                return AppColors.statusTodo;
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Task Table'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline,
                        size: 40, color: AppColors.outlineVariant),
                    const SizedBox(height: 12),
                    Text('Error loading tasks',
                        style: AppTextStyles.labelMd),
                    const SizedBox(height: 8),
                    ElevatedButton(
                        onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : FadeTransition(
                  opacity: _pageFade,
                  child: SlideTransition(
                    position: _pageSlide,
                    child: SingleChildScrollView(
                      child: Column(children: [
                        // Filter chips
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _statusFilters
                                  .map((f) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(f),
                                          selected: _filter == f,
                                          onSelected: (_) => setState(
                                              () => _filter = f),
                                          selectedColor: AppColors.primary,
                                          backgroundColor: AppColors
                                              .surfaceContainerLowest,
                                          labelStyle:
                                              AppTextStyles.bodySm.copyWith(
                                            color: _filter == f
                                                ? Colors.white
                                                : AppColors.onSurface,
                                            fontWeight: _filter == f
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            side: BorderSide(
                                              color: _filter == f
                                                  ? AppColors.primary
                                                  : AppColors.outlineVariant,
                                            ),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                        // Table
                        NotionTable(
                          columns: _columns,
                          rows: _buildRows(),
                          onRowTap: (id) =>
                              _showDetailSheet(context, id),
                          onRowReorder: _perms?.canReorderTasks == true
                              ? (orderedIds) {
                                  final reordered = <TaskModel>[];
                                  for (final id in orderedIds) {
                                    final match = _tasks
                                        .where((t) => t.id == id);
                                    if (match.isNotEmpty) {
                                      reordered.add(match.first);
                                    }
                                  }
                                  setState(() => _tasks = reordered);
                                }
                              : null,
                          emptyMessage: _filter == 'All'
                              ? 'No tasks yet'
                              : 'No $_filter tasks',
                          emptyIcon: Icons.task_outlined,
                        ),
                        const SizedBox(height: 40),
                      ]),
                    ),
                  ),
                ),
    );
  }

  void _showDetailSheet(BuildContext context, String id) {
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CommentsCountBadge extends StatelessWidget {
  final int count;
  const _CommentsCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return Text('—', style: AppTextStyles.bodySm);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.comment_outlined,
          size: 13, color: AppColors.onSurfaceVariant),
      const SizedBox(width: 3),
      Text('$count', style: AppTextStyles.dataSm),
    ]);
  }
}
