// lib/features/tasks/task_detail_sheet.dart
// Role-aware task detail panel:
//   admin / manager → full edit + comments + edit history
//   employee        → read-only fields, editable status + progress, comments
//   client          → read-only title / status / due date / price only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/task_status_options_repository.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/models/task_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/models/task_status_option.dart';
import '../../core/models/client_model.dart';
import '../../core/models/team_model.dart';
import '../../core/utils/task_permissions.dart';
import '../../core/services/n8n_service.dart';
import 'status_options_manager_sheet.dart';

class TaskDetailSheet extends StatefulWidget {
  final String taskId;
  final VoidCallback? onUpdated;

  /// When set, shows a "Move to department" action (source manager only).
  final VoidCallback? onMoveDepartment;

  /// When set, shows an "Accept into my department" action (target manager,
  /// task still in the Waiting List).
  final VoidCallback? onAcceptHandoff;

  const TaskDetailSheet({
    super.key,
    required this.taskId,
    this.onUpdated,
    this.onMoveDepartment,
    this.onAcceptHandoff,
  });

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  TaskModel? _task;
  List<ProfileModel> _allEmployees = [];
  List<TaskEditLog> _editLogs = [];
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  bool _sendingComment = false;
  String? _error;

  late TaskPermissions _perms;

  // Edit fields — used only when perms.canEditFull
  late final TextEditingController _titleCtrl = TextEditingController();
  late final TextEditingController _descCtrl = TextEditingController();
  late final TextEditingController _costCtrl = TextEditingController();
  late final TextEditingController _commentCtrl = TextEditingController();

  String _priority = 'medium';
  String _status = 'not_started';
  DateTime? _dueDate;
  double _progress = 0.0;
  List<String> _selectedAssigneeIds = [];
  bool _commentIsInternal = true;
  String? _clientId;
  List<ClientModel> _clients = [];
  String? _selectedTeamId;
  List<TeamModel> _teams = [];

  // Live comment list — built from task + optionally refetched
  List<TaskComment> _comments = [];

  // Status options loaded from column_status_options
  List<TaskStatusOption> _statusOptions = [];

  // Built-in statuses employees are allowed to set
  static const _employeeAllowed = {
    'not_started',
    'in_progress',
    'employee_done',
    'on_hold',
  };

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthNotifier>().profile;
    _perms = TaskPermissions(
      profile ??
          ProfileModel(
            id: '',
            role: 'employee',
            fullName: '',
            status: 'active',
            timezone: 'UTC',
            preferredLanguage: 'en',
            createdAt: '',
          ),
    );
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _costCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final taskData = await TaskRepository.fetchTaskDetail(widget.taskId);
      if (taskData == null) {
        _error = 'Task not found';
        return;
      }

      final task = TaskModel.fromMap(taskData);
      _task = task;
      _comments = List<TaskComment>.from(task.comments);

      // Populate edit fields
      _titleCtrl.text = task.title;
      _descCtrl.text = task.description ?? '';
      _costCtrl.text = task.cost != null ? task.cost!.toStringAsFixed(2) : '';
      _priority = task.priority;
      _status = task.status;
      _dueDate = task.dueDate != null ? DateTime.tryParse(task.dueDate!) : null;
      _progress = task.completionPercentage.toDouble();
      _selectedAssigneeIds = task.assignees.map((a) => a.profileId).toList();
      _clientId = task.clientId;
      _selectedTeamId = task.teamId;

      // Load clients for picker (admin/manager only)
      if (_perms.canEditFull) {
        _clients = await ClientRepository.fetchClients();
      }

      // Assignee picker — members of the TASK's team (not the viewer's).
      // Admin editing a Marketing task must see Marketing people.
      if (_perms.canEditFull) {
        final currentProfile = context.read<AuthNotifier>().profile;
        if (currentProfile != null) {
          if (currentProfile.isAdmin) {
            _teams = await TeamRepository.fetchAllAdmin(activeOnly: true);
          }

          String? teamId = _selectedTeamId;
          if (teamId == null) {
            // No team on the task yet — fall back to the viewer's team.
            final myTeams = await TeamRepository.fetchByLeadId(
              currentProfile.id,
            );
            teamId = myTeams.isNotEmpty
                ? myTeams.first.id
                : currentProfile.teamId;
            _selectedTeamId = teamId;
          }
          if (teamId != null) {
            _allEmployees = await TeamRepository.fetchMembersAdmin(teamId);
          } else if (currentProfile.isAdmin) {
            // Admin + teamless task → offer all active staff.
            _allEmployees = await TeamRepository.fetchAllStaffAdmin();
          }
          // Clients can never be assignees.
          _allEmployees.removeWhere((e) => e.isClient);
          if (!currentProfile.isClient &&
              !_allEmployees.any((e) => e.id == currentProfile.id)) {
            _allEmployees.insert(0, currentProfile);
          }
        }
      }

      // Edit history (admin/manager only)
      if (_perms.canSeeEditHistory) {
        _editLogs = await TaskRepository.fetchEditHistory(widget.taskId);
      }

      // Status options — admin bootstraps on first run; all roles just fetch
      final uid = context.read<AuthNotifier>().profile?.id ?? '';
      if (_perms.profile.isAdmin) {
        await TaskStatusOptionsRepository.init(uid);
      }
      _statusOptions = await TaskStatusOptionsRepository.fetchOptions();
    } catch (e) {
      _error = 'Error loading task: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onTeamChanged(String? newTeamId) async {
    if (newTeamId == null) return;
    setState(() {
      _selectedTeamId = newTeamId;
      _loading = true;
    });

    try {
      final currentProfile = context.read<AuthNotifier>().profile;
      final employees = await TeamRepository.fetchMembersAdmin(newTeamId);
      employees.removeWhere((e) => e.isClient);
      if (currentProfile != null &&
          !currentProfile.isClient &&
          !employees.any((e) => e.id == currentProfile.id)) {
        employees.insert(0, currentProfile);
      }

      setState(() {
        _allEmployees = employees;
        // Filter current assignees: keep only those in the new team
        _selectedAssigneeIds.removeWhere(
          (id) => !employees.any((e) => e.id == id),
        );
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_perms.canEditFull) {
      await _saveFullEdit();
    } else if (_perms.canEditStatus) {
      await _saveStatusAndProgress();
    }
  }

  Future<void> _saveFullEdit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Task title cannot be empty');
      return;
    }
    setState(() => _saving = true);
    try {
      final costVal = double.tryParse(_costCtrl.text.trim());
      final currentUid = context.read<AuthNotifier>().profile!.id;

      await TaskRepository.updateTask(
        id: widget.taskId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        priority: _priority,
        status: _status,
        dueDate: _dueDate?.toIso8601String().split('T').first,
        completionPercentage: _progress.round(),
        cost: costVal,
        clientId: _clientId,
        clearClient: _clientId == null,
        teamId: _selectedTeamId,
        editedBy: currentUid,
        editSummary: 'Task details updated',
      );

      await TaskRepository.updateTaskAssignees(
        widget.taskId,
        _selectedAssigneeIds,
        assignedBy: currentUid,
      );

      // Notify client via n8n → Telegram (fire-and-forget)
      if (_clientId != null) {
        try {
          final client = _clients.firstWhere((c) => c.id == _clientId);
          final phone = client.phone ?? client.whatsappNumber ?? '';
          if (phone.isNotEmpty) {
            N8nService.notifyTaskUpdate(
              clientPhone: phone,
              clientName: client.companyName,
              taskTitle: _titleCtrl.text.trim(),
              newStatus: _status,
              priority: _priority,
              dueDate: _dueDate?.toIso8601String().split('T').first,
              completionPercentage: _progress.round(),
              description: _descCtrl.text.trim().isEmpty
                  ? null
                  : _descCtrl.text.trim(),
              updatedBy: context.read<AuthNotifier>().profile?.fullName ?? '',
            );
          }
        } catch (_) {}
      }

      _showSnack('Task updated');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveStatusAndProgress() async {
    setState(() => _saving = true);
    try {
      final currentUid = context.read<AuthNotifier>().profile!.id;
      await TaskRepository.updateTaskStatusAndProgress(
        id: widget.taskId,
        status: _status,
        completionPercentage: _progress.round(),
        editedBy: currentUid,
      );
      _showSnack('Task updated');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text(
          'Are you sure you want to delete this task? This cannot be undone.',
        ),
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
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      final ok = await TaskRepository.deleteTask(widget.taskId);
      if (ok) {
        _showSnack('Task deleted');
        widget.onUpdated?.call();
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception('Deletion failed');
      }
    } catch (e) {
      _showSnack('Could not delete: $e', isError: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ── Add comment ───────────────────────────────────────────────────────────

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      final uid = context.read<AuthNotifier>().profile!.id;
      final ok = await TaskRepository.addComment(
        widget.taskId,
        uid,
        text,
        isInternal: _commentIsInternal,
      );
      if (ok) {
        _commentCtrl.clear();
        // Optimistic UI — add to local list
        final profile = context.read<AuthNotifier>().profile!;
        setState(() {
          _comments.add(
            TaskComment(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              content: text,
              isInternal: _commentIsInternal,
              createdAt: DateTime.now().toIso8601String(),
              authorName: profile.fullName,
            ),
          );
        });
      } else {
        _showSnack('Could not send comment', isError: true);
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  // ── Assignee picker ───────────────────────────────────────────────────────

  void _showAssigneePicker() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Select Assignees'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _allEmployees.length,
              itemBuilder: (_, idx) {
                final emp = _allEmployees[idx];
                final sel = _selectedAssigneeIds.contains(emp.id);
                return CheckboxListTile(
                  value: sel,
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
                  activeColor: AppColors.gold,
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
        duration: Duration(seconds: isError ? 6 : 3),
      ),
    );
  }

  Color _statusColor(String s) {
    if (_statusOptions.isNotEmpty) {
      for (final opt in _statusOptions) {
        if (opt.label == s) return opt.dartColor;
      }
    }
    return TaskStatusOptionsRepository.colorForStatus(s);
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

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // Mirror the create-task sheet: content-height sheet that scrolls freely.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _loading
            ? const SizedBox(
                height: 250,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
              )
            : _error != null
            ? SizedBox(
                height: 250,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 40,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 12),
                      Text(_error!, style: AppTextStyles.labelMd),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHandle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _buildBody(),
                    ),
                    _buildActions(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  Widget _buildBody() {
    if (_perms.profile.isClient) return _buildClientBody();
    if (_perms.canEditFull) return _buildFullEditBody();
    return _buildEmployeeBody();
  }

  // ── CLIENT view ─────────────────────────────────────────────────────────

  Widget _buildClientBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Task Details', style: AppTextStyles.headlineSm),
            TStatusChip(
              label: _task!.statusLabel,
              color: _statusColor(_task!.status),
            ),
          ],
        ),
        const Divider(height: 24),

        Text(_task!.title, style: AppTextStyles.labelMd.copyWith(fontSize: 18)),
        const SizedBox(height: 24),

        // Due date
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          label: 'Due Date',
          value: _task!.dueDateDisplay,
        ),
        const SizedBox(height: 12),

        // Price — highlighted
        if (_task!.cost != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.monetization_on_outlined,
                  color: AppColors.gold,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PRICE', style: AppTextStyles.labelCaps),
                    const SizedBox(height: 2),
                    Text(
                      'EGP ${_task!.cost!.toStringAsFixed(2)}',
                      style: AppTextStyles.headlineSm.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  // ── ADMIN / MANAGER view (full edit) ────────────────────────────────────

  Widget _buildFullEditBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Task Details', style: AppTextStyles.headlineSm),
            TStatusChip(
              label: _task!.statusLabel,
              color: _statusColor(_task!.status),
            ),
          ],
        ),
        const Divider(height: 24),

        // Title
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'TITLE',
            hintText: 'Enter task title',
            prefixIcon: Icon(Icons.title, color: AppColors.gold, size: 18),
          ),
        ),
        const SizedBox(height: 14),

        // Description
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

        // Priority
        _SectionLabel('PRIORITY'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _PriorityChip(
              'low',
              'Low',
              AppColors.statusLow,
              _priority,
              (v) => setState(() => _priority = v),
            ),
            _PriorityChip(
              'medium',
              'Medium',
              AppColors.statusMedium,
              _priority,
              (v) => setState(() => _priority = v),
            ),
            _PriorityChip(
              'high',
              'High',
              AppColors.statusHigh,
              _priority,
              (v) => setState(() => _priority = v),
            ),
            _PriorityChip(
              'critical',
              'Critical',
              AppColors.error,
              _priority,
              (v) => setState(() => _priority = v),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Status
        Row(
          children: [
            _SectionLabel('STATUS'),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.tune, size: 14, color: AppColors.gold),
              label: Text(
                _perms.profile.isAdmin ? 'Edit Options' : 'View Options',
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
              .map(
                (opt) => _StatusChip(
                  opt.label,
                  opt.displayLabel,
                  _status,
                  (v) => setState(() => _status = v),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),

        // Due date
        _SectionLabel('DUE DATE'),
        const SizedBox(height: 8),
        _DatePickerRow(
          date: _dueDate,
          onPick: (d) => setState(() => _dueDate = d),
        ),
        const SizedBox(height: 18),

        // Progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel('PROGRESS'),
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

        // Cost
        TextField(
          controller: _costCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        // Department (only for Admin)
        if (_perms.profile.isAdmin) ...[
          _SectionLabel('DEPARTMENT'),
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
        _SectionLabel('CLIENT'),
        const SizedBox(height: 8),
        if (_clients.isEmpty)
          Text(
            'No clients — create one in the Clients section.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
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
                  child: Text(c.companyName, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (val) => setState(() => _clientId = val),
          ),
        const SizedBox(height: 18),

        // Assignees
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel('ASSIGNEES'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: AppColors.gold),
              onPressed: _showAssigneePicker,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_selectedAssigneeIds.isEmpty)
          Text('No assignees', style: AppTextStyles.bodySm)
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

        const SizedBox(height: 24),
        const Divider(),

        // Comments
        if (_perms.canSeeComments) ...[
          _buildCommentsSection(),
          const SizedBox(height: 8),
          const Divider(),
        ],

        // Edit history
        if (_perms.canSeeEditHistory && _editLogs.isNotEmpty) ...[
          _buildEditHistorySection(),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  // ── EMPLOYEE view ────────────────────────────────────────────────────────

  Widget _buildEmployeeBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _task!.title,
                style: AppTextStyles.headlineSm,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TStatusChip(
              label: _task!.statusLabel,
              color: _statusColor(_task!.status),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Read-only meta chips
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            TPriorityBadge(priority: _task!.priorityLabel),
            if (_task!.dueDate != null)
              _MetaChip(
                icon: Icons.calendar_today_outlined,
                label: _task!.dueDateDisplay,
              ),
          ],
        ),
        const Divider(height: 24),

        // Description (read-only)
        if ((_task!.description ?? '').isNotEmpty) ...[
          _SectionLabel('DESCRIPTION'),
          const SizedBox(height: 6),
          Text(
            _task!.description!,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
        ],

        // Assignees (read-only)
        if (_task!.assignees.isNotEmpty) ...[
          _SectionLabel('ASSIGNED TO'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _task!.assignees
                .map(
                  (a) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TAvatar(name: a.fullName, size: 20),
                      const SizedBox(width: 6),
                      Text(a.fullName, style: AppTextStyles.bodySm),
                      if (a.isLead) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.star, size: 12, color: AppColors.gold),
                      ],
                    ],
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
        ],

        // Status — editable (built-in employee-allowed + all custom options)
        Row(
          children: [
            _SectionLabel('UPDATE STATUS'),
            const Spacer(),
            TextButton.icon(
              icon: Icon(
                Icons.info_outline,
                size: 14,
                color: AppColors.outlineVariant,
              ),
              label: Text(
                'View Options',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.outlineVariant,
                ),
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
              .where((o) => !o.isDefault || _employeeAllowed.contains(o.label))
              .map(
                (opt) => _StatusChip(
                  opt.label,
                  opt.displayLabel,
                  _status,
                  (v) => setState(() => _status = v),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),

        // Progress — editable
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel('MY PROGRESS'),
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
        const SizedBox(height: 8),
        const Divider(),

        // Comments
        if (_perms.canSeeComments) _buildCommentsSection(),

        const SizedBox(height: 16),
      ],
    );
  }

  // ── Shared: comments ─────────────────────────────────────────────────────

  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionLabel('COMMENTS'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_comments.length}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_comments.isEmpty)
          Text('No comments yet', style: AppTextStyles.bodySm)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _comments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = _comments[i];
              return _CommentTile(comment: c);
            },
          ),

        if (_perms.canAddComment) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Add a comment… use @name to mention',
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
                  // Internal / visible toggle (admin/manager only)
                  if (_perms.canEditFull)
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
                  _sendingComment
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gold,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.send_rounded,
                            color: AppColors.gold,
                          ),
                          onPressed: _sendComment,
                        ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Shared: edit history ─────────────────────────────────────────────────

  Widget _buildEditHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('EDIT HISTORY'),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _editLogs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final log = _editLogs[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log.editorName, style: AppTextStyles.labelMd),
                        if (log.summary != null)
                          Text(
                            log.summary!,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    log.timeDisplay,
                    style: AppTextStyles.dataSm.copyWith(fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActions() {
    final busy = _saving || _deleting;

    // Client — close only
    if (_perms.profile.isClient) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ),
      );
    }

    // Employee — cancel + save (status/progress only)
    if (!_perms.canEditFull) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: busy ? null : _save,
                child: _saving ? _Spinner() : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      );
    }

    // Admin / Manager — delete + cancel + save
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          if (widget.onAcceptHandoff != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onAcceptHandoff!();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusDone,
                ),
                icon: const Icon(Icons.check, size: 18, color: Colors.white),
                label: const Text(
                  'Accept into my department',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.onMoveDepartment != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onMoveDepartment!();
                      },
                icon: const Icon(
                  Icons.swap_horiz,
                  size: 18,
                  color: AppColors.gold,
                ),
                label: const Text('Move to another department'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              // Compact icon-only delete — leaves room for Cancel + Save.
              SizedBox(
                width: 48,
                child: OutlinedButton(
                  onPressed: busy ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: EdgeInsets.zero,
                  ),
                  child: _deleting
                      ? _Spinner(color: AppColors.error)
                      : const Icon(Icons.delete_outline, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: busy ? null : _save,
                  child: _saving ? _Spinner() : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// Reusable local widgets
// ════════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: AppTextStyles.labelCaps),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.gold),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: AppTextStyles.bodySm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        Text(value, style: AppTextStyles.bodyMd),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.dataSm),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final TaskComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TAvatar(name: comment.authorName, size: 18),
              const SizedBox(width: 8),
              Text(
                comment.authorName,
                style: AppTextStyles.labelMd.copyWith(fontSize: 13),
              ),
              const Spacer(),
              if (comment.isInternal)
                Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              const SizedBox(width: 4),
              Text(comment.timeDisplay, style: AppTextStyles.dataSm),
            ],
          ),
          const SizedBox(height: 6),
          Text(comment.content, style: AppTextStyles.bodyMd),
        ],
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  final DateTime? date;
  final ValueChanged<DateTime> onPick;
  const _DatePickerRow({this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              date != null
                  ? '${date!.year}-'
                        '${date!.month.toString().padLeft(2, '0')}-'
                        '${date!.day.toString().padLeft(2, '0')}'
                  : 'Select date…',
              style: AppTextStyles.bodyMd.copyWith(
                color: date != null
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
    );
  }
}

// Inline spinner that fits inside buttons
class _Spinner extends StatelessWidget {
  final Color color;
  const _Spinner({this.color = AppColors.gold});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

// ── Chip helpers ─────────────────────────────────────────────────────────────

class _PriorityChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final String selected;
  final ValueChanged<String> onSelect;
  const _PriorityChip(
    this.value,
    this.label,
    this.color,
    this.selected,
    this.onSelect,
  );

  @override
  Widget build(BuildContext context) {
    final sel = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => onSelect(value),
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
}

class _StatusChip extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onSelect;
  const _StatusChip(this.value, this.label, this.selected, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final sel = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => onSelect(value),
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
