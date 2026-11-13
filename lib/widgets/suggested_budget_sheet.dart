import 'package:flutter/material.dart';

import '../services/suggested_budget_service.dart';
import '../utils/currency_format.dart';

Future<double?> showSuggestedBudgetSheet({
  required BuildContext context,
  required SuggestedBudget suggestion,
  required String currencySymbol,
  bool allowApply = true,
  VoidCallback? onReviewUnclassified,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SuggestedBudgetBreakdown(
        suggestion: suggestion,
        currencySymbol: currencySymbol,
        allowApply: allowApply,
        onReviewUnclassified: onReviewUnclassified,
      );
    },
  );
}

class SuggestedBudgetBreakdown extends StatelessWidget {
  const SuggestedBudgetBreakdown({
    super.key,
    required this.suggestion,
    required this.currencySymbol,
    this.allowApply = true,
    this.onReviewUnclassified,
  });

  final SuggestedBudget suggestion;
  final String currencySymbol;
  final bool allowApply;
  final VoidCallback? onReviewUnclassified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final months = suggestion.completedMonths.clamp(
      0,
      suggestedBudgetLookbackMonths,
    );
    final coverage = suggestion.historyCoveragePercent;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
              mediaQuery.size.height * 0.8, // Constrain max height safely
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suggested monthly budget',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Uses Regular spending from up to six completed months, plus a 10% buffer. Unknown spending is excluded; more classification may change the suggestion.',
                  triggerMode: TooltipTriggerMode.tap,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.info_outline, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              coverage == null
                  ? 'Based on $months months of regular spending.'
                  : 'Based on $months months · ${coverage.toStringAsFixed(1)}% of spending classified.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (suggestion.unknownCount > 0 && onReviewUnclassified != null)
              TextButton(
                onPressed: onReviewUnclassified,
                child: const Text('Classify remaining expenses'),
              ),
            const SizedBox(height: 16),
            _SummaryRow(
              label: 'Regular recurring expenses',
              amount: suggestion.recurringTotal,
              currencySymbol: currencySymbol,
            ),
            _SummaryRow(
              label: 'Other regular spending',
              amount: suggestion.miscAverage,
              currencySymbol: currencySymbol,
            ),
            _SummaryRow(
              label: 'Buffer (${(suggestedBudgetBufferRate * 100).round()}%)',
              amount: suggestion.buffer,
              currencySymbol: currencySymbol,
            ),
            const Divider(height: 24),
            _SummaryRow(
              label: 'Recommended budget',
              amount: suggestion.amount,
              currencySymbol: currencySymbol,
              emphasize: true,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (suggestion.recurringItems.isNotEmpty) ...[
                    Text(
                      'Recurring items averaged in',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final item in suggestion.recurringItems)
                      _SuggestedItemTile(
                        item: item,
                        currencySymbol: currencySymbol,
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (suggestion.miscItems.isNotEmpty) ...[
                    Text(
                      'Misc items averaged in',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final item in suggestion.miscItems)
                      _SuggestedItemTile(
                        item: item,
                        currencySymbol: currencySymbol,
                      ),
                  ],
                ],
              ),
            ),
            if (allowApply) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, suggestion.amount),
                child: const Text('Use this budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    required this.currencySymbol,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final String currencySymbol;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatFullCurrency(amount, currencySymbol), style: style),
        ],
      ),
    );
  }
}

class _SuggestedItemTile extends StatelessWidget {
  const _SuggestedItemTile({required this.item, required this.currencySymbol});

  final SuggestedBudgetItem item;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(item.label),
      subtitle: Text(
        '${item.category} · billed across ${item.monthsSeen} month'
        '${item.monthsSeen == 1 ? '' : 's'}',
      ),
      trailing: Text(
        formatFullCurrency(item.monthlyAverage, currencySymbol),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      children: [
        for (final transaction in item.sourceTransactions)
          ListTile(
            dense: true,
            title: Text(
              transaction.description.trim().isEmpty
                  ? transaction.category
                  : transaction.description,
            ),
            subtitle: Text(
              '${transaction.date.year}-'
              '${transaction.date.month.toString().padLeft(2, '0')}-'
              '${transaction.date.day.toString().padLeft(2, '0')}',
            ),
            trailing: Text(
              formatFullCurrency(transaction.amount, currencySymbol),
            ),
          ),
      ],
    );
  }
}
