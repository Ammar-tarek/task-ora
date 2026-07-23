// lib/core/widgets/notion_table.dart
// Notion-style database table with:
//  • Column visibility management
//  • Drag-to-reorder rows (ReorderableListView)
//  • Swipe-to-delete rows (Dismissible)
//  • Responsive horizontal scroll on narrow screens

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Defines a column in the Notion table.
class NotionColumn {
  final String key;
  final String label;
  final IconData icon;
  final int flex;
  final bool removable;
  bool visible;

  NotionColumn({
    required this.key,
    required this.label,
    this.icon = Icons.text_fields,
    this.flex = 1,
    this.removable = false,
    this.visible = true,
  });
}

/// A single row of data for the table.
class NotionRow {
  final String id;
  final Map<String, Widget> cells;

  const NotionRow({required this.id, required this.cells});
}

/// Notion-style database table widget.
class NotionTable extends StatefulWidget {
  final List<NotionColumn> columns;
  final List<NotionRow> rows;
  final VoidCallback? onAddRow;
  final VoidCallback? onAddColumn;
  final void Function(String rowId)? onRowTap;

  /// Called with the row ID when the user swipes a row to delete.
  final void Function(String rowId)? onRowDelete;

  /// Called with the new ordered list of row IDs after a drag-to-reorder.
  final void Function(List<String> orderedIds)? onRowReorder;
  final String emptyMessage;
  final IconData emptyIcon;

  const NotionTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onAddRow,
    this.onAddColumn,
    this.onRowTap,
    this.onRowDelete,
    this.onRowReorder,
    this.emptyMessage = 'No data yet',
    this.emptyIcon = Icons.inbox_outlined,
  });

  @override
  State<NotionTable> createState() => _NotionTableState();
}

class _NotionTableState extends State<NotionTable>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // Local ordered copy so drag-reorder feels instant before the callback fires.
  late List<NotionRow> _orderedRows;

  @override
  void initState() {
    super.initState();
    _orderedRows = List.from(widget.rows);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(NotionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync when the parent pushes new rows (e.g. after a reload).
    if (widget.rows != oldWidget.rows) {
      _orderedRows = List.from(widget.rows);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  List<NotionColumn> get _visibleCols =>
      widget.columns.where((c) => c.visible).toList();

  void _showColumnOptions(NotionColumn col) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ColumnOptionsSheet(
        columns: widget.columns,
        onChanged: () => setState(() {}),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final row = _orderedRows.removeAt(oldIndex);
      _orderedRows.insert(newIndex, row);
    });
    widget.onRowReorder?.call(_orderedRows.map((r) => r.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final cols = _visibleCols;
    final canReorder = widget.onRowReorder != null && _orderedRows.isNotEmpty;

    return FadeTransition(
      opacity: _fadeAnim,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = MediaQuery.of(context).size.width < 600;
          final double minTableWidth = isMobile ? 680.0 : 820.0;
          final bool needsScroll = constraints.maxWidth < minTableWidth;

          Widget tableBody;

          if (_orderedRows.isEmpty) {
            tableBody = _buildEmptyState();
          } else if (canReorder) {
            // ReorderableListView for drag-to-reorder
            tableBody = ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _orderedRows.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) => Material(
                elevation: 6,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                child: child,
              ),
              itemBuilder: (ctx, i) {
                final row = _orderedRows[i];
                return _buildDraggableRow(
                  key: ValueKey(row.id),
                  index: i,
                  row: row,
                  cols: cols,
                );
              },
            );
          } else {
            tableBody = Column(
              mainAxisSize: MainAxisSize.min,
              children: _orderedRows
                  .asMap()
                  .entries
                  .map((e) => _buildRow(e.key, e.value, cols))
                  .toList(),
            );
          }

          Widget fullTable = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(cols),
              const Divider(height: 1),
              tableBody,
              if (widget.onAddRow != null) _buildAddRow(),
            ],
          );

          if (needsScroll) {
            fullTable = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minTableWidth, child: fullTable),
            );
          }

          return Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: fullTable,
          );
        },
      ),
    );
  }

  // ── Row builders ──────────────────────────────────────────────────────────

  /// Row used when reordering is enabled — includes drag handle + swipe-delete.
  Widget _buildDraggableRow({
    required Key key,
    required int index,
    required NotionRow row,
    required List<NotionColumn> cols,
  }) {
    Widget rowContent = _buildRowContent(
      index,
      row,
      cols,
      showHandle: true,
      key: widget.onRowDelete == null ? key : null,
    );

    if (widget.onRowDelete != null) {
      rowContent = Dismissible(
        key: key,
        direction: DismissDirection.endToStart,
        background: _buildDismissBackground(),
        confirmDismiss: (_) async {
          return await _confirmDelete(row.id);
        },
        onDismissed: (_) {
          setState(() => _orderedRows.removeWhere((r) => r.id == row.id));
          widget.onRowDelete!(row.id);
        },
        child: rowContent,
      );
    }

    return rowContent;
  }

  /// Plain animated row (no reorder, optional swipe-delete).
  Widget _buildRow(int index, NotionRow row, List<NotionColumn> cols) {
    Widget rowContent = TweenAnimationBuilder<double>(
      key: ValueKey(row.id),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 60).clamp(0, 400)),
      curve: Curves.easeOut,
      builder: (_, val, child) => Opacity(
        opacity: val,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - val)),
          child: child,
        ),
      ),
      child: _buildRowContent(index, row, cols, showHandle: false),
    );

    if (widget.onRowDelete != null) {
      rowContent = Dismissible(
        key: ValueKey(row.id),
        direction: DismissDirection.endToStart,
        background: _buildDismissBackground(),
        confirmDismiss: (_) async => await _confirmDelete(row.id),
        onDismissed: (_) {
          setState(() => _orderedRows.removeWhere((r) => r.id == row.id));
          widget.onRowDelete!(row.id);
        },
        child: rowContent,
      );
    }

    return rowContent;
  }

  Widget _buildRowContent(
    int index,
    NotionRow row,
    List<NotionColumn> cols, {
    required bool showHandle,
    Key? key,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final paddingH = isMobile ? 8.0 : 12.0;
    final paddingV = isMobile ? 8.0 : 10.0;

    return InkWell(
      key: key,
      onTap: widget.onRowTap != null ? () => widget.onRowTap!(row.id) : null,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: index.isEven
              ? AppColors.surfaceContainerLowest
              : AppColors.background,
          border: Border(
            bottom: BorderSide(color: AppColors.outlineVariant, width: 0.5),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        child: Row(
          children: [
            // Drag handle shown only in reorder mode
            if (showHandle) ...[
              ReorderableDragStartListener(
                index: _orderedRows.indexWhere((r) => r.id == row.id),
                child: Padding(
                  padding: EdgeInsets.only(right: isMobile ? 4 : 8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: isMobile ? 14 : 16,
                    color: AppColors.outlineVariant,
                  ),
                ),
              ),
            ],
            ...cols.map(
              (col) => Expanded(
                flex: col.flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child:
                      row.cells[col.key] ??
                      Text('—', style: AppTextStyles.bodySm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dismiss helpers ───────────────────────────────────────────────────────

  Widget _buildDismissBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      color: AppColors.error.withValues(alpha: 0.12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 6),
          Text(
            'Delete',
            style: AppTextStyles.labelMd.copyWith(color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(String rowId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text(
          'Are you sure you want to delete this task permanently?',
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
    return result ?? false;
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(List<NotionColumn> cols) {
    final canReorder = widget.onRowReorder != null && _orderedRows.isNotEmpty;
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 8 : 10,
      ),
      child: Row(
        children: [
          // Spacer matching drag handle width in reorder mode
          if (canReorder) SizedBox(width: isMobile ? 18 : 24),
          ...cols.map(
            (col) => Expanded(
              flex: col.flex,
              child: GestureDetector(
                onTap: () => _showColumnOptions(col),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      col.icon,
                      size: isMobile ? 11 : 13,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        col.label.toUpperCase(),
                        style: AppTextStyles.labelCaps.copyWith(
                          color: AppColors.onSurface,
                          fontSize: isMobile ? 8.5 : 10,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.onAddColumn != null)
            GestureDetector(
              onTap: widget.onAddColumn,
              child: Container(
                width: isMobile ? 24 : 28,
                height: isMobile ? 24 : 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.add,
                  size: isMobile ? 12 : 14,
                  color: AppColors.gold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Empty state & Add row ─────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(widget.emptyIcon, size: 40, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(
            widget.emptyMessage,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to create one',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow() {
    return InkWell(
      onTap: widget.onAddRow,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 15, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'New',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for managing column visibility.
class _ColumnOptionsSheet extends StatefulWidget {
  final List<NotionColumn> columns;
  final VoidCallback onChanged;

  const _ColumnOptionsSheet({required this.columns, required this.onChanged});

  @override
  State<_ColumnOptionsSheet> createState() => _ColumnOptionsSheetState();
}

class _ColumnOptionsSheetState extends State<_ColumnOptionsSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('Manage Columns', style: AppTextStyles.headlineSm),
          const SizedBox(height: 4),
          Text('Toggle which columns are visible', style: AppTextStyles.bodySm),
          const SizedBox(height: 12),
          const Divider(),
          ...widget.columns.map(
            (col) => SwitchListTile(
              value: col.visible,
              onChanged: (v) {
                setState(() => col.visible = v);
                widget.onChanged();
              },
              title: Row(
                children: [
                  Icon(col.icon, size: 16, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Text(col.label, style: AppTextStyles.bodyMd),
                ],
              ),
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
