// lib/features/tasks/task_detail_sheet.dart
// Role-aware task detail panel:
//   admin / manager → full edit + comments + edit history
//   employee        → read-only fields, editable status + progress, comments
//   client          → read-only title / status / due date / price only

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/providers/workspace_scope_notifier.dart';
import '../../core/constants/departments.dart';
import '../../core/theme/app_theme.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/task_status_options_repository.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/models/task_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/utils/app_time.dart';
import '../../core/models/task_status_option.dart';
import '../../core/models/client_model.dart';
import '../../core/models/team_model.dart';
import '../../core/utils/task_permissions.dart';
import '../../core/utils/task_handoff_lock.dart';
import '../../core/services/n8n_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'status_options_manager_sheet.dart';

class TaskDetailSheet extends StatefulWidget {
  final String taskId;
  final VoidCallback? onUpdated;

  /// When set, shows a "Move to department" action (source manager only).
  final VoidCallback? onMoveDepartment;

  const TaskDetailSheet({
    super.key,
    required this.taskId,
    this.onUpdated,
    this.onMoveDepartment,
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
  bool _hiddenFromClient = false;
  String? _clientId;
  List<ClientModel> _clients = [];
  String? _selectedTeamId;
  List<TeamModel> _teams = [];

  // Montage-only reel payment status: 'paid' | 'not_paid' | 'done'.
  String? _paymentStatus;
  String? _initialPaymentStatus;
  bool _isMontageTask = false;

  // Live comment list — built from task + optionally refetched
  List<TaskComment> _comments = [];

  // Review info (from task_approvals): last decision, reason, reviewer name.
  bool _reviewing = false;
  String? _reviewDecision; // 'approved' | 'changes_requested'
  String? _reviewReason;
  String? _reviewerName;

  // Status options loaded from column_status_options
  List<TaskStatusOption> _statusOptions = [];

  // When false, the admin/manager full-edit form shows only the same inputs as
  // the Create Task sheet (title, description, due date, assignees, comments).
  // The other definition inputs are hidden; their loaded values are still sent
  // on save, so nothing is wiped. Flip to true to restore the full editor.
  static const bool _showAdvancedEditFields = false;

  // Built-in statuses employees are allowed to set
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
    // Capture scope before any await (avoids using context across async gaps).
    final scope = context.read<WorkspaceScopeNotifier>();
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
      // Stored as a UTC instant; show the Egypt wall-clock in the picker so it
      // round-trips through AppTime.fromCairoToUtc on save.
      final parsedDue =
          task.dueDate != null ? DateTime.tryParse(task.dueDate!) : null;
      _dueDate = parsedDue != null ? AppTime.cairo(parsedDue) : null;
      _progress = task.completionPercentage.toDouble();
      _selectedAssigneeIds = task.assignees.map((a) => a.profileId).toList();
      _clientId = task.clientId;
      _selectedTeamId = task.teamId;
      _hiddenFromClient = task.hiddenFromClient;
      _paymentStatus = task.paymentStatus;
      _initialPaymentStatus = task.paymentStatus;
      _isMontageTask = scope.isMontageTeam(task.teamId);

      // Review info from task_approvals (reviewer / decision / reason).
      final rawAp = taskData['task_approvals'];
      Map<String, dynamic>? ap;
      if (rawAp is List && rawAp.isNotEmpty) {
        ap = rawAp.first as Map<String, dynamic>;
      } else if (rawAp is Map) {
        ap = rawAp.cast<String, dynamic>();
      }
      _reviewDecision = ap?['review_decision'] as String?;
      _reviewReason = ap?['review_reason'] as String?;
      _reviewerName = null;
      final reviewerId = ap?['reviewer_id'] as String?;
      if (reviewerId != null) {
        try {
          final r = await TaskRepository.fetchProfileName(reviewerId);
          _reviewerName = r;
        } catch (_) {}
      }

      // Load clients for picker (admin/manager only)
      if (_perms.canEditFull) {
        _clients = await ClientRepository.fetchClients();
      }
      if (!mounted) return;

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
      if (!mounted) return;

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
    // Sending department / non-receiving viewer on a transferred task: no write.
    if (_senderReadOnly) return;
    // Receiving manager on a transferred task: assignment only, definition locked.
    if (_assignmentOnly) {
      await _saveAssignmentOnly();
    } else if (_perms.canEditFull) {
      await _saveFullEdit();
    } else if (_perms.canEditStatus) {
      await _saveStatusAndProgress();
    }
  }

  /// Receiving manager on a transferred task: persist ONLY the assignee set.
  /// The task definition is locked (DB-enforced); we never send it here.
  Future<void> _saveAssignmentOnly() async {
    setState(() => _saving = true);
    try {
      final currentUid = context.read<AuthNotifier>().profile!.id;
      await TaskRepository.updateTaskAssignees(
        widget.taskId,
        _selectedAssigneeIds,
        assignedBy: currentUid,
      );
      if (!mounted) return;
      widget.onUpdated?.call();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnack('Could not update assignment: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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

      final updaterName = context.read<AuthNotifier>().profile?.fullName ?? '';
      await TaskRepository.updateTask(
        id: widget.taskId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        priority: _priority,
        status: _status,
        dueDate: _dueDate == null
            ? null
            : AppTime.fromCairoToUtc(_dueDate!.year, _dueDate!.month,
                    _dueDate!.day, _dueDate!.hour, _dueDate!.minute)
                .toIso8601String(),
        completionPercentage: _progress.round(),
        cost: costVal,
        clientId: _clientId,
        clearClient: _clientId == null,
        teamId: _selectedTeamId,
        hiddenFromClient: _hiddenFromClient,
        editedBy: currentUid,
        editSummary: 'Task details updated',
      );

      await TaskRepository.updateTaskAssignees(
        widget.taskId,
        _selectedAssigneeIds,
        assignedBy: currentUid,
      );

      await _persistPaymentIfChanged(currentUid);

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
              dueDate: _dueDate?.toIso8601String(),
              completionPercentage: _progress.round(),
              description: _descCtrl.text.trim().isEmpty
                  ? null
                  : _descCtrl.text.trim(),
              updatedBy: updaterName,
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

  /// Employee submits an assigned task for internal review (→ 'employee_done').
  /// Writes the submission to task_approvals via the secure RPC.
  Future<void> _submitForReview() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.submitForReview(widget.taskId);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Submitted for review');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Employee pulls their own submission back out (while teammates have not
  /// submitted yet, so the task has not reached review).
  Future<void> _unsubmitForReview() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.unsubmitForReview(widget.taskId);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Submission undone');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Employee accepts the assignment.
  Future<void> _acceptAssignment() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.respondToAssignment(widget.taskId, accept: true);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Task accepted');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Employee rejects the assignment (reason required). Does NOT change status.
  Future<void> _rejectAssignment() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Reject Assignment'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'Why can you not take this task?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      _showSnack('A reason is required', isError: true);
      return;
    }
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.respondToAssignment(
        widget.taskId,
        accept: false,
        reason: reason,
      );
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Assignment rejected');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Employee moves an accepted task to In Progress.
  Future<void> _startWork() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.startWork(widget.taskId);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Work started');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Assignee pulls a submitted task back OUT of review → In Progress, so they
  /// can keep working before a manager reviews it.
  Future<void> _withdrawReview() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.withdrawFromReview(widget.taskId);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Withdrawn from review');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Manager/admin approves an employee-done task → 'completed'.
  Future<void> _approve() async {
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.reviewTask(widget.taskId, approved: true);
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Task approved');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Manager/admin returns an employee-done task for changes (reason required).
  Future<void> _requestChanges() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Request Changes'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'What needs to change before approval?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Send Back', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return; // cancelled
    if (reason.isEmpty) {
      _showSnack('A reason is required', isError: true);
      return;
    }
    setState(() => _reviewing = true);
    try {
      final err = await TaskRepository.reviewTask(
        widget.taskId,
        approved: false,
        reason: reason,
      );
      if (err != null) {
        _showSnack(err, isError: true);
        return;
      }
      _showSnack('Sent back for changes');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _reviewing = false);
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
      await _persistPaymentIfChanged(currentUid);
      _showSnack('Task updated');
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Montage-only: persist the reel payment status when it changed. The server
  /// trigger rejects it if the caller is not an admin/team manager.
  Future<void> _persistPaymentIfChanged(String uid) async {
    if (!_isMontageTask) return;
    if (_paymentStatus == null || _paymentStatus == _initialPaymentStatus) return;
    await TaskRepository.updatePaymentStatus(
      widget.taskId,
      _paymentStatus!,
      updatedBy: uid,
    );
    _initialPaymentStatus = _paymentStatus;
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

  bool _archiving = false;
  bool _incrementing = false;

  // ── Increment (create numbered copies) ─────────────────────────────────────

  Future<void> _incrementTask() async {
    if (_task == null) return;
    final uid = context.read<AuthNotifier>().profile!.id;
    final countCtrl = TextEditingController(text: '1');

    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Increment Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This task becomes "${_task!.title} 1"; copies continue from 2. '
              'Copies keep the client and department only — no assignees.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: countCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'How many copies?',
                prefixIcon: Icon(
                  Icons.numbers,
                  color: AppColors.gold,
                  size: 18,
                ),
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
              final n = int.tryParse(countCtrl.text.trim()) ?? 0;
              Navigator.pop(ctx, n);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (count == null) return;
    if (count <= 0) {
      _showSnack('Enter a number greater than 0', isError: true);
      return;
    }
    if (count > 100) {
      _showSnack('Maximum 100 copies at a time', isError: true);
      return;
    }

    setState(() => _incrementing = true);
    try {
      final created = await TaskRepository.incrementTask(
        task: _task!,
        count: count,
        createdBy: uid,
      );
      if (created > 0) {
        _showSnack('Created $created cop${created == 1 ? 'y' : 'ies'}');
        widget.onUpdated?.call();
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception('Increment failed');
      }
    } catch (e) {
      _showSnack('Could not increment: $e', isError: true);
    } finally {
      if (mounted) setState(() => _incrementing = false);
    }
  }

  Future<void> _toggleArchive() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null || _task == null) return;

    final isCurrentlyArchived = _task!.isArchived;
    final actionName = isCurrentlyArchived ? 'unarchive and retrieve' : 'archive';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(isCurrentlyArchived ? 'Retrieve Task' : 'Archive Task'),
        content: Text(
          'Are you sure you want to $actionName "${_task!.title}"?',
        ),
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
            child: Text(isCurrentlyArchived ? 'Retrieve' : 'Archive'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _archiving = true);

    try {
      bool ok;
      if (isCurrentlyArchived) {
        ok = await TaskRepository.unarchiveTasks([_task!.id]);
      } else {
        ok = await TaskRepository.archiveTask(_task!.id, profileId: profile.id);
      }

      if (ok) {
        _showSnack(
          isCurrentlyArchived
              ? 'Task retrieved and restored to active tasks'
              : 'Task archived successfully',
        );
        widget.onUpdated?.call();
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception('Operation failed');
      }
    } catch (e) {
      _showSnack('Could not update archive status: $e', isError: true);
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  // ── Add comment ───────────────────────────────────────────────────────────

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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
            child: const Text('Insert Link'),
          ),
        ],
      ),
    );
  }

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
      if (!mounted) return;
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
              // ignore: deprecated_member_use
              cacheExtent: 250.0,
              addRepaintBoundaries: true,
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

  // ── Handoff (direct-transfer) UI gates — mirror the DB guards/policies ─────
  // DB is authoritative; these only decide what to show/enable.
  bool get _viewerGlobalAdmin =>
      _perms.profile.isAdmin || _perms.profile.isSuperAdmin; // == DB is_global_admin
  bool get _taskTransferred =>
      _task != null && (_task!.handoffFromTeamId ?? '').isNotEmpty;
  String? get _viewerTeam => _perms.profile.teamId;
  bool get _viewerReceivingSide =>
      _task?.teamId != null && _viewerTeam != null && _viewerTeam == _task!.teamId;
  /// Sending department (and any non-receiving, non-admin viewer) on a
  /// transferred task: strictly read-only.
  bool get _senderReadOnly =>
      _taskTransferred && !_viewerGlobalAdmin && !_viewerReceivingSide;
  /// Task-definition editable: only a global admin on a transferred task; the
  /// normal role rules apply on any non-transferred task.
  bool get _defEditable => !_taskTransferred || _viewerGlobalAdmin;
  /// Receiving-team manager may manage assignment only (no definition edit).
  bool get _assignmentOnly =>
      _taskTransferred && !_viewerGlobalAdmin && _viewerReceivingSide && _perms.canEditFull;

  /// This viewer's own assignee row (employee), or null.
  TaskAssignee? get _myAssignment {
    final uid = context.read<AuthNotifier>().profile?.id;
    if (uid == null || _task == null) return null;
    return _task!.assigneeFor(uid);
  }

  /// Banner about the employee's own assignment response (pending / rejected).
  /// Empty when accepted, legacy (null), or the viewer is not an assignee.
  List<Widget> _assignmentBanner() {
    final a = _myAssignment;
    if (a == null) return const [];
    if (a.response == 'pending') {
      return [
        _banner(
          AppColors.statusInProgress,
          Icons.help_outline,
          'Awaiting your response',
          'Accept or reject this assignment below.',
        ),
      ];
    }
    if (a.response == 'rejected') {
      return [
        _banner(
          AppColors.error,
          Icons.block,
          'You rejected this assignment',
          (a.responseReason ?? '').trim().isEmpty ? null : a.responseReason,
        ),
      ];
    }
    return const [];
  }

  /// Small coloured banner used by the assignment/review notices.
  Widget _banner(Color color, IconData icon, String title, String? body) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.labelMd.copyWith(color: color)),
            ],
          ),
          if (body != null && body.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, style: AppTextStyles.bodySm),
          ],
        ],
      ),
    );
  }

  /// Banner showing the last review outcome (reviewer, decision, reason).
  /// Empty when there is nothing to show.
  List<Widget> _reviewBanner() {
    final isChanges =
        _task?.status == 'changes_requested' || _reviewDecision == 'changes_requested';
    if (_reviewDecision == null && _task?.status != 'changes_requested') {
      return const [];
    }
    final color = isChanges ? AppColors.error : AppColors.statusDone;
    final title = isChanges ? 'Changes requested' : 'Approved';
    final who = _reviewerName != null ? ' by $_reviewerName' : '';
    return [
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isChanges ? Icons.undo : Icons.verified, size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  '$title$who',
                  style: AppTextStyles.labelMd.copyWith(color: color),
                ),
              ],
            ),
            if (isChanges && (_reviewReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_reviewReason!, style: AppTextStyles.bodySm),
            ],
          ],
        ),
      ),
    ];
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
    context.watch<LocaleController>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // Mirror the create-task sheet: content-height sheet that scrolls freely.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
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
    // Transferred task: the sending department (and anyone not on the receiving
    // team, bar a global admin) is read-only — route to the employee view,
    // whose actions are gated to close-only below.
    if (_perms.canEditFull && !_senderReadOnly) return _buildFullEditBody();
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
            Text(S.t('task_details'), style: AppTextStyles.headlineSm),
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
            Text(S.t('task_details'), style: AppTextStyles.headlineSm),
            TStatusChip(
              label: _task!.statusLabel,
              color: _statusColor(_task!.status),
            ),
          ],
        ),
        const Divider(height: 24),

        ..._reviewBanner(),

        // Transferred into this department: definition is locked; the manager
        // may only manage assignment. (DB enforces this too.)
        if (_assignmentOnly) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 16, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transferred task — definition is locked. You can only assign it to your team.',
                    style: AppTextStyles.bodySm,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Title
        TextField(
          controller: _titleCtrl,
          readOnly: _assignmentOnly,
          decoration: InputDecoration(
            labelText: S.t('title').toUpperCase(),
            hintText: S.t('task_title'),
            prefixIcon: const Icon(Icons.title, color: AppColors.gold, size: 18),
          ),
        ),
        const SizedBox(height: 14),

        // Description
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          readOnly: _assignmentOnly,
          decoration: InputDecoration(
            labelText: S.t('description').toUpperCase(),
            hintText: S.t('description'),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.notes, color: AppColors.gold, size: 18),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Advanced definition inputs are hidden so this form mirrors the
        // Create Task sheet; their loaded values are still saved.
        if (_showAdvancedEditFields) ...[
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

        // Montage-only reel PAYMENT STATUS selector (Paid / Not Paid / Done).
        // Distinct from completion status above. Editable by admin/manager;
        // employees see it read-only (server trigger also enforces this).
        if (_isMontageTask) ...[
          _SectionLabel('PAYMENT STATUS'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: TaskModel.montagePaymentOptions
                .map(
                  (opt) => _StatusChip(
                    opt.$1,
                    opt.$2,
                    _paymentStatus ?? '',
                    _perms.canEditFull
                        ? (v) => setState(() => _paymentStatus = v)
                        : (_) {},
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
        ],
        ],

        // Due date
        _SectionLabel('DUE DATE'),
        const SizedBox(height: 8),
        _DatePickerRow(
          date: _dueDate,
          onPick: (d) => setState(() => _dueDate = d),
        ),
        const SizedBox(height: 18),

        if (_showAdvancedEditFields) ...[
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
        if (_clientId != null) ...[
          const SizedBox(height: 8),
          Container(
            // Clip the tile's ink/overlay to the rounded box so the Material
            // layer and the white background don't overlap at the corners.
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              activeThumbColor: AppColors.gold,
              value: _hiddenFromClient,
              onChanged: (v) => setState(() => _hiddenFromClient = v),
              title: Text(
                'Hide from client',
                style: AppTextStyles.bodyMd,
              ),
              subtitle: Text(
                _hiddenFromClient
                    ? 'The client will not see this task in their portal.'
                    : 'The client can see this task in their portal.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                _hiddenFromClient
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _hiddenFromClient
                    ? AppColors.error
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        ],

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

        ..._assignmentBanner(),
        ..._reviewBanner(),

        // Description (read-only)
        if ((_task!.description ?? '').isNotEmpty) ...[
          _SectionLabel('DESCRIPTION'),
          const SizedBox(height: 6),
          ClickableCommentText(
            text: _task!.description!,
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

        // Status — READ ONLY (management-controlled). Employees move the task
        // through the workflow actions in the action bar, not by editing here.
        _SectionLabel('STATUS'),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TStatusChip(
            label: _task!.statusLabel,
            color: _statusColor(_task!.status),
          ),
        ),
        const SizedBox(height: 18),

        // Progress — READ ONLY (set by management).
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel('PROGRESS'),
            Text(
              '${_task!.completionPercentage}%',
              style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _task!.completionPercentage.clamp(0, 100) / 100.0,
            minHeight: 6,
            backgroundColor: AppColors.outlineVariant,
            color: AppColors.gold,
          ),
        ),
        const SizedBox(height: 18),

        // Deadline — read-only for employees (set by management).
        _SectionLabel('DEADLINE'),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(_task?.dueDateDisplay ?? '—', style: AppTextStyles.bodyMd),
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
          Column(
            children: _comments.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CommentTile(comment: c),
            )).toList(),
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
                  // Insert Link — any commenter (including employees) can add a
                  // direct link into their comment.
                  IconButton(
                    icon: const Icon(Icons.link, color: AppColors.gold, size: 20),
                    tooltip: 'Insert Link into Comment',
                    onPressed: _showInsertLinkDialog,
                  ),
                  // Internal / visible-to-client toggle — managers/admins only.
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
        Column(
          children: _editLogs.map((log) => Padding(
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
          )).toList(),
        ),
      ],
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  /// Marketing workspace hides the Increment and Archive task options.
  bool get _isMarketing =>
      context.read<WorkspaceScopeNotifier>().effectiveDepartment ==
      Department.marketing;

  Widget _buildActions() {
    final busy = _saving || _deleting || _incrementing || _reviewing;

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

    // Transferred task + read-only viewer (sending department, or anyone not on
    // the receiving team and not a global admin): close only, no write actions.
    if (_senderReadOnly) {
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

    // Employee — assignment response + workflow actions + save deadline.
    if (!_perms.canEditFull) {
      final a = _myAssignment;
      final pending = a?.response == 'pending';
      final s = _task?.status ?? '';
      final canStart = s == 'not_started';
      // This employee already submitted their part — waiting on teammates.
      final mineSubmitted = a?.submittedAt != null;
      final canSubmit = !mineSubmitted && const {
        'not_started', 'in_progress', 'changes_requested', 'on_hold'
      }.contains(s);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            if (pending) ...[
              // Must accept/reject the assignment before working on it.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _rejectAssignment,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject Task'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: busy ? null : _acceptAssignment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusDone,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _reviewing
                          ? _Spinner()
                          : const Icon(Icons.check, size: 18, color: Colors.white),
                      label: const Text('Accept Task',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ] else ...[
              if (canStart) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _startWork,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusInProgress,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                    label: const Text('Start Work',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (canSubmit) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _submitForReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusDone,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _reviewing
                        ? _Spinner()
                        : const Icon(Icons.task_alt, size: 18, color: Colors.white),
                    label: const Text('Submit for Review',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Partial submit: I'm done but teammates are not, so the task has
              // not gone to review yet. Show a waiting note + let me undo.
              if (mineSubmitted && s != 'employee_done') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.statusDone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top,
                          size: 18, color: AppColors.statusDone),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You submitted your part — waiting for your '
                          'teammate(s) to submit before it goes for review.',
                          style: AppTextStyles.bodySm,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _unsubmitForReview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusInProgress,
                      side: const BorderSide(color: AppColors.statusInProgress),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _reviewing
                        ? _Spinner(color: AppColors.statusInProgress)
                        : const Icon(Icons.undo, size: 18),
                    label: const Text('Undo my submission'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Withdraw (retreat) a submitted task back to In Progress — the
              // assignee may pull it out of review before a manager reviews it.
              if (s == 'employee_done') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _withdrawReview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusInProgress,
                      side: const BorderSide(color: AppColors.statusInProgress),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _reviewing
                        ? _Spinner(color: AppColors.statusInProgress)
                        : const Icon(Icons.undo, size: 18),
                    label: const Text('Withdraw from Review'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Close'),
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
          // Internal review: a manager/admin approves a submitted task into
          // 'completed', or sends it back for changes (reason required). Shown
          // for any Pending Review task across all departments.
          if (_task != null && _task!.status == 'employee_done') ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusDone,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _reviewing
                        ? _Spinner()
                        : const Icon(Icons.verified, size: 18, color: Colors.white),
                    label: const Text(
                      'Approve',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _requestChanges,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Request Changes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // After approval: a manager/admin can REOPEN a completed task by
          // requesting changes again (reason required). Needs the relaxed
          // review_task RPC (PROPOSED_review_changes_after_approve.sql).
          if (_task != null && _task!.status == 'completed') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _requestChanges,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Request Changes'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Direct-transfer model: no Accept/Reject Handoff actions. Re-transfer
          // is blocked for a department once transferred (admin override only).
          if (widget.onMoveDepartment != null &&
              (!_taskTransferred || _viewerGlobalAdmin)) ...[
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
          // Increment — create numbered copies. Locked on a transferred task
          // (it would clone a definition the receiving dept cannot own-edit).
          // Hidden in the Marketing workspace (team's request).
          if (_task != null && _defEditable && !_isMarketing) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _incrementTask,
                icon: _incrementing
                    ? _Spinner(color: AppColors.gold)
                    : const Icon(
                        Icons.control_point_duplicate,
                        size: 18,
                        color: AppColors.gold,
                      ),
                label: const Text('Increment task (numbered copies)'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              // Compact icon-only delete — hidden on a transferred task (a dept
              // cannot delete it; admin override only). DB enforces this too.
              if (_task != null &&
                  TaskHandoffLock.canDelete(_task!, isGlobalAdmin: _viewerGlobalAdmin)) ...[
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
              ],
              // Archive / Unarchive toggle for admins & managers (not on a
              // transferred task for a non-admin — definition is locked).
              // Hidden in the Marketing workspace (team's request).
              if (_perms.canEditFull && _task != null && _defEditable && !_isMarketing) ...[
                SizedBox(
                  width: 48,
                  child: OutlinedButton(
                    onPressed: busy ? null : _toggleArchive,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.gold),
                      padding: EdgeInsets.zero,
                    ),
                    child: _archiving
                        ? _Spinner(color: AppColors.gold)
                        : Icon(
                            _task!.isArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            size: 20,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
                  child: _saving
                      ? _Spinner()
                      : Text(_assignmentOnly ? 'Save Assignment' : 'Save Changes'),
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
    child: Text(S.t(text), style: AppTextStyles.labelCaps),
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

class ClickableCommentText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const ClickableCommentText({
    super.key,
    required this.text,
    required this.style,
  });

  static Future<void> openUrl(String urlStr) async {
    final cleanUrl = urlStr.trim();
    if (cleanUrl.isEmpty) return;
    try {
      final formattedUrl = cleanUrl.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? cleanUrl
          : 'https://$cleanUrl';
      final uri = Uri.parse(formattedUrl);

      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        final formattedUrl = 'https://${cleanUrl.replaceAll(RegExp(r'^https?://', caseSensitive: false), '')}';
        await launchUrl(Uri.parse(formattedUrl), mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  @override
  State<ClickableCommentText> createState() => _ClickableCommentTextState();
}

class _ClickableCommentTextState extends State<ClickableCommentText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();

    final text = widget.text;
    final style = widget.style;

    if (text.isEmpty) return Text('', style: style);

    final mdRegex = RegExp(
      r'\[([^\]]+)\]\((https?://[^\s\)]+|www\.[^\s\)]+|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}[^\s\)]*)\)',
      caseSensitive: false,
    );
    final rawRegex = RegExp(
      r'(https?://[^\s<]+|www\.[^\s<]+)',
      caseSensitive: false,
    );

    final List<_CommentLinkMatch> linkMatches = [];

    for (final match in mdRegex.allMatches(text)) {
      final label = match.group(1) ?? 'Link';
      final url = match.group(2) ?? '';
      linkMatches.add(_CommentLinkMatch(
        start: match.start,
        end: match.end,
        label: label,
        url: url,
      ));
    }

    for (final match in rawRegex.allMatches(text)) {
      final start = match.start;
      final end = match.end;
      final url = match.group(0) ?? '';
      final overlaps = linkMatches.any((lm) => start < lm.end && end > lm.start);
      if (!overlaps && url.isNotEmpty) {
        linkMatches.add(_CommentLinkMatch(
          start: start,
          end: end,
          label: url,
          url: url,
        ));
      }
    }

    linkMatches.sort((a, b) => a.start.compareTo(b.start));

    if (linkMatches.isEmpty) {
      return SelectableText(text, style: style);
    }

    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final lm in linkMatches) {
      if (lm.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, lm.start),
          style: style,
        ));
      }

      final urlToOpen = lm.url;
      final rec = TapGestureRecognizer()
        ..onTap = () => ClickableCommentText.openUrl(urlToOpen);
      _recognizers.add(rec);

      spans.add(
        TextSpan(
          text: lm.label,
          style: style.copyWith(
            color: AppColors.gold,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.bold,
          ),
          recognizer: rec,
        ),
      );

      lastEnd = lm.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

class _CommentLinkMatch {
  final int start;
  final int end;
  final String label;
  final String url;

  _CommentLinkMatch({
    required this.start,
    required this.end,
    required this.label,
    required this.url,
  });
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
          ClickableCommentText(text: comment.content, style: AppTextStyles.bodyMd),
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
        if (d == null) return;
        if (!context.mounted) return;
        // Then pick the time (hour + minute) so the deadline is exact.
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(
            date ?? DateTime(d.year, d.month, d.day, 17, 0),
          ),
        );
        final h = t?.hour ?? date?.hour ?? 17;
        final m = t?.minute ?? date?.minute ?? 0;
        onPick(DateTime(d.year, d.month, d.day, h, m));
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
                        '${date!.day.toString().padLeft(2, '0')} '
                        '${date!.hour.toString().padLeft(2, '0')}:'
                        '${date!.minute.toString().padLeft(2, '0')}'
                  : 'Select date & time…',
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
      label: Text(S.t(label)),
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
      label: Text(S.t(label)),
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
