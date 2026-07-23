// lib/features/tasks/status_options_manager_sheet.dart
// Bottom sheet for managing task status options.
// Admin can add, edit color, and delete non-built-in options.
// Non-admin users see a read-only list.

import 'package:flutter/material.dart';
import '../../core/models/task_status_option.dart';
import '../../core/repositories/task_status_options_repository.dart';
import '../../core/theme/app_theme.dart';

class StatusOptionsManagerSheet extends StatefulWidget {
  final bool isAdmin;
  final String? adminUserId;
  final VoidCallback? onChanged;

  const StatusOptionsManagerSheet({
    super.key,
    required this.isAdmin,
    this.adminUserId,
    this.onChanged,
  });

  @override
  State<StatusOptionsManagerSheet> createState() =>
      _StatusOptionsManagerSheetState();
}

class _StatusOptionsManagerSheetState extends State<StatusOptionsManagerSheet> {
  List<TaskStatusOption> _options = [];
  bool _loading = true;

  static const _palette = [
    '#6D4C41',
    '#1565C0',
    '#755B00',
    '#2E7D32',
    '#BA1A1A',
    '#747878',
    '#6A0DAD',
    '#E65100',
    '#00838F',
    '#283593',
    '#558B2F',
    '#C62828',
    '#AD1457',
    '#00695C',
    '#F57F17',
    '#4527A0',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.isAdmin && widget.adminUserId != null) {
      await TaskStatusOptionsRepository.init(widget.adminUserId!);
    }
    final opts = await TaskStatusOptionsRepository.fetchOptions();
    if (mounted)
      setState(() {
        _options = opts;
        _loading = false;
      });
  }

  // ── Add ──────────────────────────────────────────────────────────────────────

  Future<void> _addOption() async {
    final result = await _showDialog(title: 'Add Status Option');
    if (result == null) return;
    final opt = await TaskStatusOptionsRepository.addOption(
      label: result['label']!,
      color: result['color']!,
      userId: widget.adminUserId!,
    );
    if (opt != null) {
      setState(() => _options.add(opt));
      widget.onChanged?.call();
    } else {
      _snack('Failed to add option', isError: true);
    }
  }

  // ── Edit ─────────────────────────────────────────────────────────────────────

  Future<void> _editOption(TaskStatusOption option) async {
    final result = await _showDialog(
      title: 'Edit Option',
      initialLabel: option.displayLabel,
      initialColor: option.color,
      labelReadOnly: option.isDefault,
    );
    if (result == null) return;
    final newLabel = option.isDefault ? option.label : result['label']!;
    final ok = await TaskStatusOptionsRepository.updateOption(
      option.id,
      label: newLabel,
      color: result['color']!,
    );
    if (ok) {
      await _load();
      widget.onChanged?.call();
    } else {
      _snack('Failed to update option', isError: true);
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  Future<void> _deleteOption(TaskStatusOption option) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Status Option'),
        content: Text(
          'Delete "${option.displayLabel}"?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await TaskStatusOptionsRepository.deleteOption(option.id);
    if (ok) {
      setState(() => _options.removeWhere((o) => o.id == option.id));
      widget.onChanged?.call();
    } else {
      _snack('Failed to delete option', isError: true);
    }
  }

  // ── Dialog ───────────────────────────────────────────────────────────────────

  Future<Map<String, String>?> _showDialog({
    required String title,
    String initialLabel = '',
    String initialColor = '#888888',
    bool labelReadOnly = false,
  }) {
    final labelCtrl = TextEditingController(text: initialLabel);
    String selectedColor = initialColor;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label field
              if (!labelReadOnly)
                TextField(
                  controller: labelCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'LABEL',
                    hintText: 'e.g. Waiting for Delivery',
                  ),
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: AppColors.outlineVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      initialLabel,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('PICK COLOR', style: AppTextStyles.labelCaps),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _palette.map((hex) {
                  final color = _hexColor(hex);
                  final sel = hex == selectedColor;
                  return GestureDetector(
                    onTap: () => setD(() => selectedColor = hex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: sel
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.55),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: sel
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  );
                }).toList(),
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
                final label = labelReadOnly
                    ? initialLabel
                    : labelCtrl.text.trim();
                if (!labelReadOnly && label.isEmpty) return;
                Navigator.pop(ctx, {'label': label, 'color': selectedColor});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Color _hexColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF888888);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Text('Status Options', style: AppTextStyles.headlineSm),
                const Spacer(),
                if (widget.isAdmin)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Option'),
                    onPressed: _addOption,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : _options.isEmpty
                ? const Center(child: Text('No status options found'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _options.length,
                    itemBuilder: (_, i) {
                      final opt = _options[i];
                      return ListTile(
                        leading: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: opt.dartColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          opt.displayLabel,
                          style: AppTextStyles.bodyMd,
                        ),
                        subtitle: opt.isDefault
                            ? Text(
                                'Built-in',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.outlineVariant,
                                ),
                              )
                            : null,
                        trailing: widget.isAdmin
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    color: AppColors.gold,
                                    tooltip: 'Edit color',
                                    onPressed: () => _editOption(opt),
                                  ),
                                  if (!opt.isDefault)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      color: AppColors.error,
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteOption(opt),
                                    ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
