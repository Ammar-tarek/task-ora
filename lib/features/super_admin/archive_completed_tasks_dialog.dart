// lib/features/super_admin/archive_completed_tasks_dialog.dart
// Interactive dialog for Super Admin to archive tasks by date range, status, or completed status.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/theme/app_theme.dart';

class ArchiveCompletedTasksDialog extends StatefulWidget {
  const ArchiveCompletedTasksDialog({super.key});

  @override
  State<ArchiveCompletedTasksDialog> createState() =>
      _ArchiveCompletedTasksDialogState();
}

class _ArchiveCompletedTasksDialogState
    extends State<ArchiveCompletedTasksDialog> {
  int _tabIndex = 0; // 0 = Custom Filter / Time Range, 1 = Quick Completed
  bool _loading = false;
  bool _counting = false;
  int _matchingCount = 0;
  Map<String, dynamic>? _result;
  String? _errorMsg;

  // Filter fields
  DateTimeRange? _dateRange;
  String _selectedStatus = 'all'; // 'all', 'completed', 'in_progress', 'not_started', 'on_hold', 'employee_done', 'client_approved', 'client_rejected'

  final List<Map<String, String>> _statusOptions = [
    {'key': 'all', 'label': 'All Statuses'},
    {'key': 'completed', 'label': 'Completed'},
    {'key': 'in_progress', 'label': 'In Progress'},
    {'key': 'not_started', 'label': 'To Do / Not Started'},
    {'key': 'on_hold', 'label': 'On Hold'},
    {'key': 'employee_done', 'label': 'Employee Done'},
    {'key': 'client_approved', 'label': 'Client Approved'},
    {'key': 'client_rejected', 'label': 'Client Rejected'},
  ];

  @override
  void initState() {
    super.initState();
    _updateMatchingCount();
  }

  Future<void> _updateMatchingCount() async {
    if (_tabIndex == 1) return;
    setState(() => _counting = true);
    final count = await TaskRepository.countUnarchivedTasks(
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
      statusFilter: _selectedStatus,
    );
    if (!mounted) return;
    setState(() {
      _matchingCount = count;
      _counting = false;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.surfaceContainerLowest,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      _updateMatchingCount();
    }
  }

  Future<void> _handleArchive() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null || !profile.isSuperAdmin) {
      setState(() => _errorMsg = 'Super Admin authorization required.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    Map<String, dynamic> res;
    if (_tabIndex == 0) {
      res = await TaskRepository.archiveTasksByFilter(
        superAdminId: profile.id,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        statusFilter: _selectedStatus,
      );
    } else {
      res = await TaskRepository.archiveCompletedTasks(
        superAdminId: profile.id,
      );
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['error'] != null) {
        _errorMsg = res['error'].toString();
      } else {
        _result = res;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const CircularProgressIndicator(color: AppColors.gold),
          const SizedBox(height: 20),
          Text(
            'Archiving tasks…',
            style: AppTextStyles.headlineSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Updating visibility rules across all task views.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (_result != null) {
      final archived = _result!['archivedCount'] as int? ?? 0;
      final skipped = _result!['skippedCount'] as int? ?? 0;
      final rawTs = _result!['timestamp'] as String? ?? '';
      final ts = rawTs.length >= 19 ? rawTs.substring(0, 19).replaceAll('T', ' ') : rawTs;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.statusDone,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Archive Complete',
                  style: AppTextStyles.headlineSm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Newly Archived Tasks', '$archived', AppColors.gold),
                if (_tabIndex == 1) ...[
                  const SizedBox(height: 8),
                  _summaryRow('Already Archived (Skipped)', '$skipped', AppColors.onSurfaceVariant),
                ],
                const SizedBox(height: 8),
                _summaryRow('Execution Time', ts, AppColors.onSurface),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Archived tasks are now hidden from active task lists. Super Admins can manage or retrieve them anytime in Archived Tasks Manager.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: const Color(0xFF000000),
              ),
              child: const Text('Close'),
            ),
          ),
        ],
      );
    }

    final df = DateFormat('MMM dd, yyyy');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.archive_outlined,
              color: AppColors.gold,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Archive Tasks (Super Admin)',
                style: AppTextStyles.headlineSm,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mode Switcher Tabs
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _tabIndex = 0);
                    _updateMatchingCount();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _tabIndex == 0 ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: _tabIndex == 0
                          ? Border.all(color: AppColors.gold.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Text(
                      'Date Range / Filter',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelMd.copyWith(
                        color: _tabIndex == 0 ? AppColors.gold : AppColors.onSurfaceVariant,
                        fontWeight: _tabIndex == 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _tabIndex == 1 ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: _tabIndex == 1
                          ? Border.all(color: AppColors.gold.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Text(
                      'Completed Only',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelMd.copyWith(
                        color: _tabIndex == 1 ? AppColors.gold : AppColors.onSurfaceVariant,
                        fontWeight: _tabIndex == 1 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_errorMsg != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMsg!,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_tabIndex == 0) ...[
          // Custom Date Range Picker
          Text('Select Date Range', style: AppTextStyles.labelMd),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range_outlined, color: AppColors.gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dateRange == null
                          ? 'All Time (No date constraint)'
                          : '${df.format(_dateRange!.start)} – ${df.format(_dateRange!.end)}',
                      style: AppTextStyles.bodyMd,
                    ),
                  ),
                  if (_dateRange != null)
                    GestureDetector(
                      onTap: () {
                        setState(() => _dateRange = null);
                        _updateMatchingCount();
                      },
                      child: Icon(Icons.close, size: 18, color: AppColors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Status Selector Dropdown
          Text('Task Status', style: AppTextStyles.labelMd),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStatus,
                isExpanded: true,
                dropdownColor: AppColors.surfaceContainerLowest,
                items: _statusOptions
                    .map(
                      (opt) => DropdownMenuItem(
                        value: opt['key']!,
                        child: Text(opt['label']!, style: AppTextStyles.bodyMd),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStatus = val);
                    _updateMatchingCount();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live Preview Badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_list_alt, color: AppColors.gold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: _counting
                      ? Text('Calculating matching tasks…', style: AppTextStyles.bodySm)
                      : Text(
                          '$_matchingCount task(s) match selected range & status.',
                          style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                        ),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            'This action will hide all currently completed tasks from Managers and Employees to keep active task views clean.',
            style: AppTextStyles.bodyMd,
          ),
        ],

        const SizedBox(height: 16),
        _bulletPoint('No task history, comments, or attachments will be deleted.'),
        _bulletPoint('Super Admins can retrieve or unarchive tasks anytime from the Archived Tasks screen.'),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _handleArchive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF000000),
                ),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(
                  _tabIndex == 0 ? 'Archive Selected Range' : 'Archive Completed Tasks',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String val, Color valColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        Text(
          val,
          style: AppTextStyles.labelMd.copyWith(color: valColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
