// lib/features/super_admin/archived_tasks_screen.dart
// Interactive screen for Super Admins and Admins to manage, search,
// and retrieve (unarchive/restore) archived tasks.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/task_model.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/theme/app_theme.dart';
import '../tasks/task_detail_sheet.dart';

class ArchivedTasksScreen extends StatefulWidget {
  const ArchivedTasksScreen({super.key});

  @override
  State<ArchivedTasksScreen> createState() => _ArchivedTasksScreenState();
}

class _ArchivedTasksScreenState extends State<ArchivedTasksScreen> {
  List<TaskModel> _archivedTasks = [];
  Set<String> _selectedIds = {};
  bool _loading = true;
  bool _processing = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tasks = await TaskRepository.fetchArchivedTasks();
    if (!mounted) return;
    setState(() {
      _archivedTasks = tasks;
      _selectedIds.clear();
      _loading = false;
    });
  }

  List<TaskModel> get _filteredTasks {
    if (_searchQuery.trim().isEmpty) return _archivedTasks;
    final q = _searchQuery.toLowerCase();
    return _archivedTasks.where((t) {
      final titleMatch = t.title.toLowerCase().contains(q);
      final clientMatch = (t.clientName ?? '').toLowerCase().contains(q);
      final statusMatch = t.statusLabel.toLowerCase().contains(q);
      return titleMatch || clientMatch || statusMatch;
    }).toList();
  }

  Future<void> _unarchiveSingle(TaskModel task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Retrieve Task'),
        content: Text(
          'Are you sure you want to unarchive "${task.title}" and restore it to active tasks?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: const Text('Retrieve Task'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _processing = true);

    final ok = await TaskRepository.unarchiveTasks([task.id]);
    if (!mounted) return;
    setState(() => _processing = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task "${task.title}" has been unarchived and restored!'),
          backgroundColor: AppColors.statusDone,
        ),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not unarchive task. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _unarchiveSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Retrieve Selected Tasks'),
        content: Text(
          'Are you sure you want to unarchive $count selected task(s) and restore them to active tasks?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: Text('Retrieve $count Tasks'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _processing = true);

    final ok = await TaskRepository.unarchiveTasks(_selectedIds.toList());
    if (!mounted) return;
    setState(() => _processing = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully retrieved $count task(s)!'),
          backgroundColor: AppColors.statusDone,
        ),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to unarchive tasks.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _inspectTask(TaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskDetailSheet(
        taskId: task.id,
        onUpdated: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final canManage = profile?.isAdmin ?? false;
    final filtered = _filteredTasks;
    final allSelected = filtered.isNotEmpty && _selectedIds.length == filtered.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Archived Tasks Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search & Filter Bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search archived tasks by title, status, or client...',
                prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // ── Bulk Action Header ──────────────────────────────────────────
          if (canManage && _archivedTasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    activeColor: AppColors.gold,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds = filtered.map((t) => t.id).toSet();
                        } else {
                          _selectedIds.clear();
                        }
                      });
                    },
                  ),
                  Text(
                    'Select All (${filtered.length})',
                    style: AppTextStyles.bodySm,
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _processing ? null : _unarchiveSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.unarchive_outlined, size: 18),
                      label: Text('Retrieve (${_selectedIds.length})'),
                    ),
                ],
              ),
            ),

          const Divider(height: 1),

          // ── List View ───────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.archive_outlined,
                              size: 48,
                              color: AppColors.outlineVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No archived tasks match "$_searchQuery"'
                                  : 'No archived tasks found',
                              style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        // ignore: deprecated_member_use
                        cacheExtent: 350.0,
                        addRepaintBoundaries: true,
                        addAutomaticKeepAlives: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final task = filtered[index];
                          final isSelected = _selectedIds.contains(task.id);
                          final rawArchivedAt = task.archivedAt ?? task.createdAt;
                          final archivedDateStr = rawArchivedAt.length >= 10
                              ? rawArchivedAt.substring(0, 10)
                              : rawArchivedAt;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppColors.gold : AppColors.outlineVariant,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: Checkbox(
                                value: isSelected,
                                activeColor: AppColors.gold,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.add(task.id);
                                    } else {
                                      _selectedIds.remove(task.id);
                                    }
                                  });
                                },
                              ),
                              title: Text(
                                task.title,
                                style: AppTextStyles.labelMd,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TStatusChip(label: task.statusLabel),
                                    if (task.clientName != null)
                                      Text(
                                        'Client: ${task.clientName}',
                                        style: AppTextStyles.bodySm,
                                      ),
                                    Text(
                                      'Archived: $archivedDateStr',
                                      style: AppTextStyles.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.unarchive_outlined, color: AppColors.gold),
                                tooltip: 'Retrieve Task',
                                onPressed: () => _unarchiveSingle(task),
                              ),
                              onTap: () => _inspectTask(task),
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
