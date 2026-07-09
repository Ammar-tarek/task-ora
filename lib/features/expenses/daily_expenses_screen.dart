// lib/features/expenses/daily_expenses_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/providers/team_privileges_notifier.dart';
import '../../core/repositories/expense_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/team_filter_chip.dart';

class DailyExpensesScreen extends StatefulWidget {
  const DailyExpensesScreen({super.key});
  @override
  State<DailyExpensesScreen> createState() => _DailyExpensesScreenState();
}

class _DailyExpensesScreenState extends State<DailyExpensesScreen> {
  List<ExpenseItem> _all    = [];
  List<Map<String, dynamic>> _categories = [];
  String _cat  = 'All';
  bool _loading = true;
  TeamFilterNotifier? _teamFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _teamFilter = context.read<TeamFilterNotifier>()
        ..loadTeams()
        ..addListener(_onTeamChange);
      _load();
    });
    // Live refresh when expenses change.
    RealtimeService.instance.listen(const ['expenses'], _onRealtime);
  }

  void _onRealtime() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onTeamChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    // Refresh privileges so grants/restrictions take effect immediately.
    await context.read<TeamPrivilegesNotifier>().reload();

    // Determine team scope: admin uses switcher, manager uses their own team
    String? teamId;
    if (profile?.isAdmin == true) {
      teamId = context.read<TeamFilterNotifier>().selectedTeamId;
    } else if (profile?.isManager == true) {
      teamId = profile?.teamId;
    }

    final results = await Future.wait([
      ExpenseRepository.fetchAll(teamId: teamId),
      ExpenseRepository.fetchCategories(),
    ]);
    if (mounted) {
      setState(() {
        _all        = results[0] as List<ExpenseItem>;
        _categories = results[1] as List<Map<String, dynamic>>;
        _loading    = false;
      });
    }
  }

  List<ExpenseItem> get _filtered => _cat == 'All'
      ? _all
      : _all.where((e) => e.categoryName == _cat).toList();

  double get _total => _filtered.fold(0, (s, e) => s + e.amount);

  List<String> get _catLabels {
    final names = _categories.map((c) => c['name'] as String? ?? '').toList();
    return ['All', ...names];
  }

  IconData _categoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'food':           return Icons.restaurant_outlined;
      case 'infrastructure': return Icons.construction_outlined;
      case 'software':       return Icons.computer_outlined;
      case 'office':         return Icons.business_outlined;
      case 'transport':      return Icons.directions_car_outlined;
      case 'training':       return Icons.school_outlined;
      default:               return Icons.receipt_long_outlined;
    }
  }

  Future<void> _approveExpense(ExpenseItem e) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    await ExpenseRepository.approveExpense(e.id, profile.id);
    _load();
  }

  Future<void> _deleteExpense(ExpenseItem e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense?'),
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
    if (confirm == true) {
      await ExpenseRepository.deleteExpense(e.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile   = context.watch<AuthNotifier>().profile;
    final privs     = context.watch<TeamPrivilegesNotifier>();
    // "Manager view" = admin, a manager with the privilege, or a granted employee.
    final isManager = profile?.isAdmin == true || privs.canManageExpenses;
    final canManageExpenses = isManager;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daily Expenses'),
        actions: [
          if (isManager)
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Manage Categories',
              onPressed: () => _showManageCategories(context),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: (!isManager || canManageExpenses)
          ? FloatingActionButton(
              onPressed: () => _showAddExpense(isManager: isManager),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: AppColors.gold),
            )
          : null,
      body: Column(
        children: [
          const TeamFilterChip(),
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : Column(children: [
              // Total banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: AppColors.primary,
                child: Column(children: [
                  Text('TOTAL EXPENSES',
                    style: AppTextStyles.labelCaps.copyWith(color: Colors.white54)),
                  const SizedBox(height: 4),
                  Text('${_total.toStringAsFixed(2)} EGP',
                    style: AppTextStyles.dataLg.copyWith(
                      color: AppColors.gold, fontSize: 28)),
                  Text('${_filtered.length} record${_filtered.length == 1 ? '' : 's'}',
                    style: AppTextStyles.bodySm.copyWith(color: Colors.white54)),
                ]),
              ),

              // Category chips
              Container(
                color: AppColors.surfaceContainerLowest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _catLabels.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _cat == c,
                        onSelected: (_) => setState(() => _cat = c),
                        selectedColor: AppColors.primary,
                        labelStyle: AppTextStyles.bodySm.copyWith(
                          color: _cat == c ? Colors.white : AppColors.onSurface,
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              ),
              const Divider(height: 1),

              // List
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.receipt_long_outlined,
                            size: 64, color: AppColors.outlineVariant),
                          const SizedBox(height: 12),
                          Text('No expenses found', style: AppTextStyles.labelMd),
                        ]))
                    : RefreshIndicator(
                        color: AppColors.gold,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final e = _filtered[i];
                            return _ExpenseCard(
                              item:      e,
                              isManager: isManager,
                              icon:      _categoryIcon(e.categoryName),
                              onApprove: (isManager && e.status != 'approved')
                                  ? () => _approveExpense(e)
                                  : null,
                              onDelete:  isManager ? () => _deleteExpense(e) : null,
                            );
                          },
                        ),
                      ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _showManageCategories(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => _ManageCategoriesDialog(
        categories: _categories,
        onChanged:  _load,
      ),
    );
  }

  Future<void> _showAddExpense({required bool isManager}) async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isManager
              ? 'No categories yet. Use the category button to add some.'
              : 'No categories available. Please ask your admin to create categories.'),
        ),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _AddExpenseDialog(
        categories: _categories,
        recordedBy: context.read<AuthNotifier>().profile?.id ?? '',
        onSaved:    _load,
      ),
    );
  }
}

// ── Expense Card ────────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.item,
    required this.isManager,
    required this.icon,
    this.onApprove,
    this.onDelete,
  });
  final ExpenseItem item;
  final bool isManager;
  final IconData icon;
  final VoidCallback? onApprove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.status == 'approved'
              ? AppColors.statusDone.withValues(alpha: 0.4)
              : AppColors.outlineVariant,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description.isNotEmpty
                  ? item.description : item.categoryName,
                style: AppTextStyles.labelMd),
              const SizedBox(height: 2),
              Row(children: [
                TStatusChip(label: item.categoryName, color: AppColors.secondary),
                const SizedBox(width: 6),
                Text('· ${item.date}', style: AppTextStyles.bodySm),
              ]),
              if (item.recordedByName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('By: ${item.recordedByName}',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant, fontSize: 11)),
              ],
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${item.amount.toStringAsFixed(2)} EGP',
              style: AppTextStyles.dataMd.copyWith(
                color: AppColors.statusHigh, fontSize: 15)),
            const SizedBox(height: 4),
            _ExpenseStatusBadge(status: item.status),
          ]),
        ]),

        // Admin / manager actions
        if (isManager) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onApprove != null)
              TextButton.icon(
                icon: const Icon(Icons.check_circle_outline,
                  size: 16, color: AppColors.statusDone),
                label: Text('Approve',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.statusDone)),
                onPressed: onApprove,
              ),
            if (onDelete != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.error),
                label: Text('Delete',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.error)),
                onPressed: onDelete,
              ),
          ]),
        ],
      ]),
    );
  }
}

// ── Expense Status Badge ────────────────────────────────────────────────────

class _ExpenseStatusBadge extends StatelessWidget {
  const _ExpenseStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case 'approved':
        color = AppColors.statusDone;
        label = 'Approved';
        break;
      case 'rejected':
        color = AppColors.statusHigh;
        label = 'Rejected';
        break;
      default:
        color = AppColors.gold;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
        style: AppTextStyles.bodySm.copyWith(color: color, fontSize: 10)),
    );
  }
}

// ── Manage Categories Dialog ────────────────────────────────────────────────

class _ManageCategoriesDialog extends StatefulWidget {
  const _ManageCategoriesDialog({
    required this.categories,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> categories;
  final VoidCallback onChanged;

  @override
  State<_ManageCategoriesDialog> createState() =>
      _ManageCategoriesDialogState();
}

class _ManageCategoriesDialogState extends State<_ManageCategoriesDialog> {
  late List<Map<String, dynamic>> _cats;
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cats = List<Map<String, dynamic>>.from(widget.categories);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final ok = await ExpenseRepository.createCategory(name: name);
    if (ok) {
      _nameCtrl.clear();
      final updated = await ExpenseRepository.fetchCategories();
      if (mounted) setState(() => _cats = updated);
      widget.onChanged();
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteCategory(String id) async {
    await ExpenseRepository.deleteCategory(id);
    final updated = await ExpenseRepository.fetchCategories();
    if (mounted) setState(() => _cats = updated);
    widget.onChanged();
  }

  Future<void> _editCategory(Map<String, dynamic> cat) async {
    final ctrl = TextEditingController(text: cat['name'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      await ExpenseRepository.updateCategory(id: cat['id'] as String, name: result);
      final updated = await ExpenseRepository.fetchCategories();
      if (mounted) setState(() => _cats = updated);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Categories'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Add new
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'New Category Name',
                  hintText: 'e.g. Marketing',
                ),
                onSubmitted: (_) => _addCategory(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saving ? null : _addCategory,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _cats.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No categories yet'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _cats.length,
                    itemBuilder: (_, i) {
                      final cat = _cats[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(cat['name'] as String? ?? '',
                          style: AppTextStyles.bodyMd),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.gold),
                            tooltip: 'Rename',
                            onPressed: () => _editCategory(cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                            tooltip: 'Remove',
                            onPressed: () => _deleteCategory(
                              cat['id'] as String),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ── Add Expense Dialog ──────────────────────────────────────────────────────

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog({
    required this.categories,
    required this.recordedBy,
    required this.onSaved,
  });
  final List<Map<String, dynamic>> categories;
  final String recordedBy;
  final VoidCallback onSaved;

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _paidCtrl   = TextEditingController();

  String? _catId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) {
      _catId = widget.categories.first['id'] as String;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _catId == null) return;
    setState(() => _saving = true);
    await ExpenseRepository.createExpense(
      categoryId:  _catId!,
      amount:      double.tryParse(_amountCtrl.text.trim()) ?? 0,
      description: _descCtrl.text.trim(),
      recordedBy:  widget.recordedBy,
      date:        _date.toIso8601String().substring(0, 10),
      paidTo: _paidCtrl.text.trim().isEmpty ? null : _paidCtrl.text.trim(),
    );
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Expense'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _catId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: widget.categories.map((c) => DropdownMenuItem<String>(
                  value: c['id'] as String,
                  child: Text(c['name'] as String? ?? ''),
                )).toList(),
                onChanged: (v) => setState(() => _catId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (EGP)', prefixText: 'EGP '),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _paidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Paid To (optional)',
                  hintText: 'Vendor / supplier name',
                ),
              ),
              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Date: ${_date.day}/${_date.month}/${_date.year}',
                  style: AppTextStyles.bodyMd,
                ),
                trailing: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.gold),
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
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
