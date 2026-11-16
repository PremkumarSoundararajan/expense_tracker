import 'package:flutter/material.dart';

import '../services/budget_comparison.dart';
import '../utils/currency_format.dart';

class DailyAllowanceDialog extends StatelessWidget {
  const DailyAllowanceDialog({
    super.key,
    required this.spending,
    required this.budget,
    required this.currencySymbol,
    required this.date,
  });

  final BudgetSpending spending;
  final double budget;
  final String currencySymbol;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = spending.recordedRemaining(budget);
    final available = remaining < 0 ? 0.0 : remaining;
    final days = DateTime(date.year, date.month + 1, 0).day - date.day + 1;
    final daily = spending.dailyAllowance(budget, now: date)!;
    String money(double value) => value < 0
        ? '-${formatFullCurrency(-value, currencySymbol)}'
        : formatFullCurrency(value, currencySymbol);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Safe to spend'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            MaterialLocalizations.of(context).formatMonthYear(date),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          row('Monthly budget', money(budget)),
          row('Actual spending this month', money(spending.total)),
          if (spending.unexpected != 0) ...[
            row('Unexpected expenses excluded', money(-spending.unexpected)),
            row('Counted toward budget', money(spending.budgetRelevant)),
          ],
          const Divider(),
          row(
            remaining < 0 ? 'Over budget' : 'Remaining budget',
            money(remaining.abs()),
          ),
          row('Days left (including today)', '$days'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${money(budget)} − ${money(spending.budgetRelevant)} = ${money(remaining)}',
                  ),
                  if (remaining < 0) ...[
                    const SizedBox(height: 6),
                    const Text('No budget remains, so the allowance is zero.'),
                  ],
                  const SizedBox(height: 8),
                  const Text('Remaining budget ÷ days left'),
                  const SizedBox(height: 4),
                  Text(
                    '${money(available)} ÷ $days ≈ ${money(daily)}/day',
                    key: const ValueKey('daily-allowance-math'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Shown on Home: ${formatWholeCurrency(daily.floorToDouble(), currencySymbol)}/day (rounded down).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
