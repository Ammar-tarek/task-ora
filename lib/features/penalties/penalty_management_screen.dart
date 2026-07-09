// lib/features/penalties/penalty_management_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_privileges_notifier.dart';
import '../../core/repositories/penalty_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_theme.dart';

class PenaltyManagementScreen extends StatefulWidget {
  const PenaltyManagementScreen({super.key});
  @override
  State<PenaltyManagementScreen> createState() => _PenaltyManagementScreenState();
}

class _PenaltyManagementScreenState extends State<PenaltyManagementScreen> {
  List<PenaltyItem> _penalties = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Live refresh when penalties change.
    RealtimeService.instance.listen(const ['penalties'], _onRealtime);
  }

  void _onRealtime() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    await context.read<TeamPrivilegesNotifier>().reload();
    final canManage = profile?.isAdmin == true ||
        context.read<TeamPrivilegesNotifier>().canManagePenalties;
    // Admin sees everyone; a manager (or granted staff) sees only their team.
    final scopeTeamId = profile?.isAdmin == true ? null : profile?.teamId;
    List<PenaltyItem> data;
    if (canManage) {
      data = await PenaltyRepository.fetchAll(teamId: scopeTeamId);
    } else {
      data = await PenaltyRepository.fetchForEmployee(profile?.id ?? '');
    }
    if (mounted) setState(() { _penalties = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final profile   = context.watch<AuthNotifier>().profile;
    final privs     = context.watch<TeamPrivilegesNotifier>();
    // "Manager view" = admin, a manager with the privilege, or a granted employee.
    final isManager = profile?.isAdmin == true || privs.canManagePenalties;
    final canManagePenalties = isManager;
    final applied   = _penalties.where((p) => p.isApplied).length;
    final pending   = _penalties.length - applied;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isManager ? 'Penalty Management' : 'My Penalties'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: (isManager && canManagePenalties)
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () => _showAddDialog(profile!.id),
              child: const Icon(Icons.add, color: AppColors.gold),
            )
          : null,
      body: Column(children: [
        // Summary row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            _SummaryTile(label: 'Total',   value: '${_penalties.length}', color: AppColors.gold),
            const SizedBox(width: 12),
            _SummaryTile(label: 'Pending', value: '$pending', color: AppColors.statusInProgress),
            const SizedBox(width: 12),
            _SummaryTile(label: 'Applied', value: '$applied', color: AppColors.statusDone),
          ]),
        ),
        if (!isManager)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Only your penalties are shown here.',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.gold),
              )),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : _penalties.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.gavel_outlined, size: 64, color: AppColors.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          isManager ? 'No penalties recorded' : 'No penalties on your record',
                          style: AppTextStyles.labelMd,
                        ),
                      ]))
                  : RefreshIndicator(
                      color: AppColors.gold,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _penalties.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _PenaltyCard(
                          penalty:   _penalties[i],
                          isManager: isManager,
                          onApply: isManager ? () async {
                            await PenaltyRepository.applyPenalty(_penalties[i].id);
                            _load();
                          } : null,
                          onDelete: isManager ? () async {
                            final ok = await _confirmDelete(context);
                            if (ok) {
                              await PenaltyRepository.deletePenalty(_penalties[i].id);
                              _load();
                            }
                          } : null,
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Penalty'),
        content: const Text('Are you sure you want to delete this penalty record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _showAddDialog(String approvedBy) async {
    List<Map<String, dynamic>> types     = [];
    List<Map<String, dynamic>> employees = [];

    // Manager: restrict the employee picker to their own team. Admin: everyone.
    final profile = context.read<AuthNotifier>().profile;
    final scopeTeamId = profile?.isAdmin == true ? null : profile?.teamId;

    // Load data before opening dialog
    final results = await Future.wait([
      PenaltyRepository.fetchTypes(),
      PenaltyRepository.fetchEmployees(teamId: scopeTeamId),
    ]);
    types     = results[0];
    employees = results[1];

    if (!mounted) return;
    if (types.isEmpty || employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load penalty types or employees')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => _AddPenaltyDialog(
        types:      types,
        employees:  employees,
        approvedBy: approvedBy,
        onSaved:    _load,
      ),
    );
  }
}

// ── Add Penalty Dialog ─────────────────────────────────────────────────────

class _AddPenaltyDialog extends StatefulWidget {
  const _AddPenaltyDialog({
    required this.types,
    required this.employees,
    required this.approvedBy,
    required this.onSaved,
  });
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> employees;
  final String approvedBy;
  final VoidCallback onSaved;

  @override
  State<_AddPenaltyDialog> createState() => _AddPenaltyDialogState();
}

class _AddPenaltyDialogState extends State<_AddPenaltyDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String? _selectedEmployee;
  String? _selectedType;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.employees.isNotEmpty) {
      _selectedEmployee = widget.employees.first['id'] as String;
    }
    if (widget.types.isNotEmpty) {
      _selectedType = widget.types.first['id'] as String;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployee == null || _selectedType == null) return;

    setState(() => _saving = true);
    await PenaltyRepository.createPenalty(
      employeeId:    _selectedEmployee!,
      penaltyTypeId: _selectedType!,
      reason:        _reasonCtrl.text.trim(),
      amount:        double.tryParse(_amountCtrl.text.trim()) ?? 0,
      approvedBy:    widget.approvedBy,
      date:          _date.toIso8601String().substring(0, 10),
    );
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Penalty'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Employee picker
              DropdownButtonFormField<String>(
                value: _selectedEmployee,
                decoration: const InputDecoration(labelText: 'Employee'),
                items: widget.employees.map((e) => DropdownMenuItem<String>(
                  value: e['id'] as String,
                  child: Text(e['full_name'] as String? ?? ''),
                )).toList(),
                onChanged: (v) => setState(() => _selectedEmployee = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Type picker
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'Penalty Type'),
                items: widget.types.map((t) => DropdownMenuItem<String>(
                  value: t['id'] as String,
                  child: Text(t['name'] as String? ?? ''),
                )).toList(),
                onChanged: (v) => setState(() => _selectedType = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (EGP)', prefixText: 'EGP '),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Reason
              TextFormField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${DateFormat('d MMM y').format(_date)}',
                  style: AppTextStyles.bodyMd),
                trailing: const Icon(Icons.calendar_today_outlined, color: AppColors.gold),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add Penalty'),
        ),
      ],
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(value, style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 22)),
        Text(label, style: AppTextStyles.labelCaps.copyWith(color: color)),
      ]),
    ),
  );
}

class _PenaltyCard extends StatelessWidget {
  const _PenaltyCard({
    required this.penalty,
    required this.isManager,
    this.onApply,
    this.onDelete,
  });
  final PenaltyItem penalty;
  final bool isManager;
  final VoidCallback? onApply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TAvatar(name: penalty.employeeName, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(penalty.employeeName, style: AppTextStyles.labelMd),
            Text(penalty.penaltyType,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
          ])),
          Text('EGP ${penalty.amount.toStringAsFixed(0)}',
            style: AppTextStyles.dataLg.copyWith(color: AppColors.error, fontSize: 18)),
          if (isManager && onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.onSurfaceVariant),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text(penalty.reason, style: AppTextStyles.bodySm),
        if (penalty.approvedByName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Approved by: ${penalty.approvedByName}',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          TStatusChip(
            label: penalty.isApplied ? 'Applied' : 'Pending',
            color: penalty.isApplied ? AppColors.statusDone : AppColors.statusInProgress,
          ),
          const SizedBox(width: 8),
          Text(penalty.date, style: AppTextStyles.bodySm.copyWith(fontSize: 11)),
          const Spacer(),
          if (isManager && !penalty.isApplied && onApply != null)
            TextButton(
              onPressed: onApply,
              child: Text('Apply Deduction',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
            ),
        ]),
      ]),
    );
  }
}
