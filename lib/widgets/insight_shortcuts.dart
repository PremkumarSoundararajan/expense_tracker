import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/financial_baseline_service.dart';
import 'accent_icon_chip.dart';

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
    Widget shortcut(
      String label,
      IconData icon,
      AccentColorPair accent,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 116),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                elevation: 1,
                shadowColor: Theme.of(context).colorScheme.shadow.withValues(
                  alpha: Theme.of(context).brightness == Brightness.light
                      ? 0.08
                      : 0.14,
                ),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: ValueKey('insight-shortcut-$label'),
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AccentIconChip(
                              icon: icon,
                              accent: accent,
                              size: 40,
                              iconSize: 22,
                            ),
                            if (locked) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: accent.icon,
                                key: ValueKey('insight-lock-$label'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('insight-shortcuts'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Explore',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            shortcut(
              'Spending trends',
              Icons.trending_up,
              context.accentColors.blue,
              onTrends,
            ),
            const SizedBox(width: 12),
            shortcut(
              'Spending spots',
              Icons.storefront_outlined,
              context.accentColors.rose,
              onSpots,
            ),
            const SizedBox(width: 12),
            shortcut(
              'Suggested budget',
              Icons.calculate_outlined,
              context.accentColors.amber,
              onBudget,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Based on your baseline',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            shortcut(
              'Savings insights',
              Icons.insights_outlined,
              context.accentColors.green,
              onSavings,
              locked: !baselineReady,
            ),
            const SizedBox(width: 12),
            shortcut(
              'Spending targets',
              Icons.flag_outlined,
              context.accentColors.violet,
              onTargets,
              locked: !baselineReady,
            ),
            const SizedBox(width: 12),
            const Spacer(),
          ],
        ),
      ],
    );
  }
}
