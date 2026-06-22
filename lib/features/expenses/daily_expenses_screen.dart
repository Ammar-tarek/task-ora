// lib/features/expenses/daily_expenses_screen.dart
// Live data from Supabase — replaces previous mock-data implementation.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/expense_repository.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ExpenseRepository.fetchAll(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daily Expenses'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpense(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.gold),
      ),
      body: _loading
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
                  Text('${_total.toStringAsFixed(2)} SAR',
                    style: AppTextStyles.dataLg.copyWith(color: AppColors.gold, fontSize: 28)),
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
                          const Icon(Icons.receipt_long_outlined,
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
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.outlineVariant),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 42, height: 42,
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(_categoryIcon(e.categoryName),
                                    color: AppColors.gold, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.description.isNotEmpty ? e.description : e.categoryName,
                                      style: AppTextStyles.labelMd),
                                    const SizedBox(height: 2),
                                    Row(children: [
                                      TStatusChip(label: e.categoryName, color: AppColors.secondary),
                                      const SizedBox(width: 6),
                                      Text('· ${e.date}', style: AppTextStyles.bodySm),
                                    ]),
                                    if (e.recordedByName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text('By: ${e.recordedByName}',
                                        style: AppTextStyles.bodySm.copyWith(
                                          color: AppColors.onSurfaceVariant, fontSize: 11)),
                                    ],
                                  ],
                                )),
                                Text('${e.amount.toStringAsFixed(2)} SAR',
                                  style: AppTextStyles.dataMd.copyWith(
                                    color: AppColors.statusHigh, fontSize: 15)),
                              ]),
                            );
                          },
                        ),
                      ),
              ),
            ]),
    );
  }

  Future<void> _showAddExpense() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load expense categories')),
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

// ── Add Expense Dialog ─────────────────────────────────────────────────────

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
  final _formKey   = GlobalKey<FormState>();
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
      paidTo:      _paidCtrl.text.trim().isEmpty ? null : _paidCtrl.text.trim(),
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
                decoration: const InputDecoration(labelText: 'Amount (SAR)', prefixText: 'SAR '),
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
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
