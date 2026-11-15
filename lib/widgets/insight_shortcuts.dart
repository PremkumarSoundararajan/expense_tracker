import 'package:flutter/material.dart';

import '../services/financial_baseline_service.dart';

/// Two explicit rows keep always-available tools apart from baseline insights.
class InsightShortcuts extends StatelessWidget {
  const InsightShortcuts({
    super.key,
    required this.summary,
    required this.onTrends,
    required this.onSpots,
    required this.onBudget,
    required this.onSavings,
    required this.onTargets,
    required this.onLocked,
  });

  final FinancialBaselineSummary summary;
  final VoidCallback onTrends, onSpots, onBudget, onSavings, onTargets;
  final ValueChanged<String> onLocked;

  bool get baselineReady =>
      summary.trackedSpending > 0 &&
      baselineInsightReadiness(summary.classifiedPercentage) !=
          BaselineInsightReadiness.insufficient;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget shortcut(
      String label,
      IconData icon,
      VoidCallback action, {
      bool locked = false,
    }) {
      final onPressed = locked ? () => onLocked(label) : action;
      return Expanded(
        child: Tooltip(
          excludeFromSemantics: true,
          message: locked
              ? '$label: classify at least ${baselineInsightMinimumCoverage.toStringAsFixed(0)}% of spending by Essentiality to unlock'
              : label,
          child: Semantics(
            button: true,
            excludeSemantics: true,
            onTap: onPressed,
            label: locked ? '$label, locked' : label,
            child: OutlinedButton(
              key: ValueKey('insight-shortcut-$label'),
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                foregroundColor: locked
                    ? colors.onSurfaceVariant
                    : colors.primary,
                backgroundColor: locked ? colors.surfaceContainerLow : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 26),
                      if (locked) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          key: ValueKey('insight-lock-$label'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('insight-shortcuts'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                shortcut('Spending trends', Icons.trending_up, onTrends),
                const SizedBox(width: 12),
                shortcut('Spending spots', Icons.storefront_outlined, onSpots),
                const SizedBox(width: 12),
                shortcut(
                  'Suggested budget',
                  Icons.calculate_outlined,
                  onBudget,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                shortcut(
                  'Savings insights',
                  Icons.insights_outlined,
                  onSavings,
                  locked: !baselineReady,
                ),
                const SizedBox(width: 12),
                shortcut(
                  'Spending targets',
                  Icons.flag_outlined,
                  onTargets,
                  locked: !baselineReady,
                ),
                const SizedBox(width: 12),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
