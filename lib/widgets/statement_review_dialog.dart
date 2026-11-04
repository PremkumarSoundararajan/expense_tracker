import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../services/worker_csv_sync_service.dart';

class StatementReviewDialog extends StatefulWidget {
  const StatementReviewDialog({
    super.key,
    required this.fileName,
    required this.preview,
    required this.currencySymbol,
    this.categories = const [],
  });

  final String fileName;
  final WorkerCsvPreview preview;
  final String currencySymbol;
  final List<ExpenseCategory> categories;

  @override
  State<StatementReviewDialog> createState() => _StatementReviewDialogState();
}

class _StatementReviewDialogState extends State<StatementReviewDialog> {
  late final List<WorkerExpensePreview> _rows = List<WorkerExpensePreview>.of(
    widget.preview.rows,
  );

  @override
  Widget build(BuildContext context) {
    final readyCount = _rows.where((row) => row.willImport).length;
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final isNarrow = screenSize.width < 700;
    final dialogHeight = screenSize.height * .85;
    final dialogWidth = math.min(860.0, screenSize.width * .96);

    return Dialog(
      key: const ValueKey('statement-review-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 8 : 24,
        vertical: 12,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 860, maxHeight: dialogHeight),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 16 : 24,
                  16,
                  isNarrow ? 12 : 16,
                  10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Review statement before import',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            widget.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_rows.length} expense(s) found. Review each category; '
                    '${widget.preview.filteredCount} non-expense or unreadable '
                    'row(s) were excluded.'
                    '${widget.preview.duplicateCount > 0 ? ' ${widget.preview.duplicateCount} row(s) match transactions already in your sheet. Changed categories update the matched row; tick "Import anyway" to add another copy.' : ''}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              if (!isNarrow) _buildColumnHeaders(theme),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => isNarrow
                      ? const SizedBox(height: 8)
                      : const Divider(height: 1),
                  itemBuilder: (context, index) => isNarrow
                      ? _buildMobileRow(index, theme)
                      : _buildRow(index, theme),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 12 : 20,
                  8,
                  isNarrow ? 12 : 20,
                  12,
                ),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '$readyCount transaction(s) ready to import or update',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: _confirmButton(readyCount)),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$readyCount transaction(s) ready to import or update',
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          _confirmButton(readyCount),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _duplicateMessage(WorkerExpensePreview row) {
    final rowLabel = row.duplicateRow == null
        ? 'a matching row already in your sheet'
        : 'row ${row.duplicateRow} in your sheet';
    if (row.categoryChanged) {
      return 'Update the category in $rowLabel; tick to add another copy.';
    }
    return 'Import anyway (matches $rowLabel)';
  }

  Widget _confirmButton(int readyCount) => FilledButton.icon(
    key: const ValueKey('statement-review-confirm-import'),
    onPressed: readyCount == 0
        ? null
        : () =>
              Navigator.of(context)
                  .pop(_rows.where((row) => row.willImport).toList()),
    icon: const Icon(Icons.upload_file_outlined),
    label: const Text('Save Changes & Import'),
  );

  Widget _buildMobileRow(int index, ThemeData theme) {
    final row = _rows[index];
    final duplicateColor = theme.colorScheme.errorContainer;
    return Container(
      key: ValueKey('statement-review-row-$index'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: row.duplicate ? duplicateColor.withValues(alpha: .28) : null,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.date,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Text(
                '${widget.currencySymbol}${row.amount.toStringAsFixed(2)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (row.duplicate) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: _duplicateMessage(row),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(row.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: DropdownButtonFormField<String>(
              key: ValueKey('statement-review-category-$index-${row.category}'),
              initialValue: row.category,
              isExpanded: true,
              menuMaxHeight: 320,
              decoration: const InputDecoration(
                labelText: 'Category',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(),
              ),
              items: _optionsFor(row)
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.name,
                      child: Text(
                        category.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (category) {
                if (category == null) return;
                setState(() {
                  final selected = _optionsFor(row)
                      .where((item) => item.name == category)
                      .firstOrNull;
                  _rows[index] = row.withCategory(
                    category,
                    categoryId: selected?.id,
                  );
                });
              },
            ),
          ),
          if (row.userEdited)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: row.rememberMapping,
              title: const Text('Remember this description for future imports'),
              onChanged: (value) => setState(() {
                _rows[index] = row.withRememberMapping(value ?? false);
              }),
            ),
          if (row.duplicate)
            CheckboxListTile(
              key: ValueKey('statement-review-import-anyway-$index'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: row.importAnyway,
              title: Text(
                row.categoryChanged
                    ? 'Import as a new duplicate'
                    : _duplicateMessage(row),
              ),
              onChanged: (value) => setState(() {
                _rows[index] = row.withImportAnyway(value ?? false);
              }),
            ),
        ],
      ),
    );
  }

  List<ExpenseCategory> _optionsFor(WorkerExpensePreview row) {
    final options = widget.categories.isNotEmpty
        ? [...widget.categories]
        : [
            for (final name in reviewExpenseCategoryOptions)
              ExpenseCategory(id: name, parentId: name, name: name),
          ];
    if (!options.any((category) => category.name == row.category)) {
      options.add(
        ExpenseCategory(
          id: row.categoryId ?? row.category,
          parentId: row.category,
          name: row.category,
        ),
      );
    }
    if (!options.any((category) => category.name == 'Transfers')) {
      options.add(
        const ExpenseCategory(
          id: 'Transfers',
          parentId: 'Transfers',
          name: 'Transfers',
        ),
      );
    }
    return options;
  }

  Widget _buildColumnHeaders(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          SizedBox(width: 92, child: _columnLabel('Date', theme)),
          const SizedBox(width: 12),
          Expanded(child: _columnLabel('Description', theme)),
          SizedBox(
            width: 108,
            child: Align(
              alignment: Alignment.centerRight,
              child: _columnLabel('Amount', theme),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(width: 200, child: _columnLabel('Category', theme)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _columnLabel(String label, ThemeData theme) => Text(
    label,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _buildRow(int index, ThemeData theme) {
    final row = _rows[index];
    final duplicateColor = theme.colorScheme.errorContainer;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: row.duplicate ? duplicateColor.withValues(alpha: .28) : null,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              row.date,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [],
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: row.description,
              child: Text(
                row.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          SizedBox(
            width: 108,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${widget.currencySymbol}${row.amount.toStringAsFixed(2)}',
                maxLines: 1,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [],
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 200,
            child: Tooltip(
              message: row.categoryMatched
                  ? 'Automatically categorized. Select to change.'
                  : 'No keyword matched. Choose a category.',
              child: DropdownButton<String>(
                value: row.category,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                iconSize: 18,
                menuMaxHeight: 320,
                items: _optionsFor(row)
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.name,
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (category) {
                  if (category == null) return;
                  setState(() {
                    final selected = _optionsFor(row)
                        .where((item) => item.name == category)
                        .firstOrNull;
                    _rows[index] = row.withCategory(
                      category,
                      categoryId: selected?.id,
                    );
                  });
                },
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: row.duplicate
                ? Tooltip(
                    message: row.categoryChanged
                        ? '${_duplicateMessage(row)} Tick to append another copy.'
                        : '${_duplicateMessage(row)}. Tick to import it.',
                    child: Checkbox(
                      key: ValueKey('statement-review-import-anyway-$index'),
                      value: row.importAnyway,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) => setState(() {
                        _rows[index] = row.withImportAnyway(value ?? false);
                      }),
                    ),
                  )
                : row.userEdited
                ? Tooltip(
                    message: 'Remember category for this description',
                    child: Checkbox(
                      value: row.rememberMapping,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) => setState(() {
                        _rows[index] = row.withRememberMapping(value ?? false);
                      }),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
