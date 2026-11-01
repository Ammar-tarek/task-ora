// lib/features/sales/sales_sheet_screen.dart
// Sales-department pipeline sheet. A scrollable, editable table mirroring the
// source spreadsheet. Managers/admins (enforced by RLS) can add, edit and delete
// rows; employees view read-only. Any cell holding a URL — and the Link column —
// is tappable and opens in the browser.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/models/sales_sheet_entry.dart';
import '../../core/repositories/sales_sheet_repository.dart';
import '../../core/theme/app_theme.dart';

class SalesSheetScreen extends StatefulWidget {
  const SalesSheetScreen({super.key});

  @override
  State<SalesSheetScreen> createState() => _SalesSheetScreenState();
}

class _SalesSheetScreenState extends State<SalesSheetScreen> {
  List<SalesSheetEntry> _rows = [];
  bool _loading = true;
  bool _busy = false;

  bool get _canEdit {
    final p = context.read<AuthNotifier>().profile;
    return p != null && (p.isAdmin || p.isManager || p.isSuperAdmin);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await SalesSheetRepository.fetchAll();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  bool _isUrl(String s) {
    final t = s.trim();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  static final _arabic = RegExp(r'[؀-ۿ]');
  bool _hasArabic(String s) => _arabic.hasMatch(s);

  /// Inter (the app body font) has no Arabic glyphs, so Arabic cells render as
  /// boxes. Use Cairo (Arabic + Latin) whenever the text contains Arabic.
  TextStyle _cellStyle(String value, Color color) {
    final base = AppTextStyles.bodySm.copyWith(color: color);
    return _hasArabic(value) ? GoogleFonts.cairo(textStyle: base) : base;
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _snack('Invalid link', error: true);
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open link', error: true);
    } catch (_) {
      _snack('Could not open link', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade800 : null,
      ),
    );
  }

  Future<void> _addRow() async {
    setState(() => _busy = true);
    final id = await SalesSheetRepository.addRow();
    setState(() => _busy = false);
    if (id == null) {
      _snack('Could not add row (permission or connection).', error: true);
      return;
    }
    await _load();
  }

  Future<void> _deleteRow(SalesSheetEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Delete row'),
        content: Text(
          'Delete "${e.client.isEmpty ? 'this row' : e.client}"? This cannot be undone.',
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
    final err = await SalesSheetRepository.deleteRow(e.id);
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    await _load();
  }

  Future<void> _editField(SalesSheetEntry e, String key, String header) async {
    final ctrl = TextEditingController(text: e.valueOf(key));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text('Edit $header'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: key == 'client' || key == 'link' ? 3 : 1,
          // Cairo renders both Arabic and Latin, so typing Arabic is clear.
          style: GoogleFonts.cairo(),
          decoration: InputDecoration(
            labelText: header,
            hintText: key == 'link' ? 'https://…' : null,
          ),
        ),
        actions: [
          if (_isUrl(ctrl.text))
            TextButton.icon(
              onPressed: () => _open(ctrl.text),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final err = await SalesSheetRepository.updateField(e.id, key, value.trim());
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Sheet'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Add row',
              onPressed: _busy ? null : _addRow,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _rows.isEmpty
              ? _empty(canEdit)
              : _table(canEdit),
      floatingActionButton: (!_loading && canEdit && _rows.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addRow,
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Add row'),
            )
          : null,
    );
  }

  Widget _empty(bool canEdit) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined,
                size: 48, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No rows yet', style: AppTextStyles.labelMd),
            const SizedBox(height: 8),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: const Text('Add the first row'),
              )
            else
              Text('Only managers can add rows.',
                  style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant)),
          ],
        ),
      );

  Widget _table(bool canEdit) {
    final cols = SalesSheetEntry.columns;
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            AppColors.gold.withValues(alpha: 0.10),
          ),
          border: TableBorder.all(color: AppColors.outlineVariant, width: 0.5),
          columns: [
            for (final c in cols)
              DataColumn(
                label: Text(c.header,
                    style: AppTextStyles.labelCaps
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
            if (canEdit) const DataColumn(label: Text('')),
          ],
          rows: [
            for (final e in _rows)
              DataRow(
                cells: [
                  for (final c in cols) DataCell(_cell(e, c.key, c.header, canEdit)),
                  if (canEdit)
                    DataCell(IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      onPressed: () => _deleteRow(e),
                    )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(SalesSheetEntry e, String key, String header, bool canEdit) {
    final value = e.valueOf(key);
    final isLink = _isUrl(value);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: isLink
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_new, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    key == 'link' ? 'Open link' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              value.isEmpty ? (canEdit ? 'Tap to add' : '—') : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _cellStyle(
                value,
                value.isEmpty ? AppColors.onSurfaceVariant : AppColors.onSurface,
              ),
            ),
    );

    // Tap behaviour:
    //  - a URL cell opens the link;
    //  - editors edit via long-press (URL cells) or tap (plain cells).
    if (isLink) {
      return InkWell(
        onTap: () => _open(value),
        onLongPress: canEdit ? () => _editField(e, key, header) : null,
        child: content,
      );
    }
    return InkWell(
      onTap: canEdit ? () => _editField(e, key, header) : null,
      child: content,
    );
  }
}
