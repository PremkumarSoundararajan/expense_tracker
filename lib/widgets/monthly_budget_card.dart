import 'package:flutter/material.dart';

import '../services/monthly_rollover_service.dart';
import '../services/suggested_budget_service.dart';
import '../utils/currency_format.dart';
import '../utils/transaction_period_format.dart';
import 'month_selector.dart';

class MonthlyBudgetCard extends StatelessWidget {
  const MonthlyBudgetCard({
    super.key,
    required this.currentSpent,
    this.regularSpent,
    this.plannedOccasionalSpent = 0,
    this.unexpectedOccasionalSpent = 0,
    required this.currencySymbol,
    required this.monthlyTarget,
    this.rolloverRecap,
    required this.onCalendarPressed,
    required this.onSetTargetPressed,
    this.now,
    this.selectedMonth,
    this.availableMonths = const [],
    this.onMonthSelected,
    this.suggestedBudget,
    this.onSuggestedBudgetPressed,
  });

  final double currentSpent;
  final double? regularSpent;
  final double plannedOccasionalSpent;
  final double unexpectedOccasionalSpent;
  final String currencySymbol;
  final double? monthlyTarget;
  final MonthlyRolloverRecap? rolloverRecap;
  final VoidCallback onCalendarPressed;
  final VoidCallback onSetTargetPressed;
  final DateTime? now;
  final DateTime? selectedMonth;
  final List<DateTime> availableMonths;
  final ValueChanged<DateTime>? onMonthSelected;
  final SuggestedBudget? suggestedBudget;
  final VoidCallback? onSuggestedBudgetPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentDate = now ?? DateTime.now();
    final month = selectedMonth ?? monthStart(currentDate);
    final isCurrentMonth = isSameMonth(month, currentDate);
    final totalDaysInMonth = DateUtils.getDaysInMonth(
      month.year,
      month.month,
    );
    final daysRemaining = isCurrentMonth
        ? (totalDaysInMonth - currentDate.day) + 1
        : 0;
    final target = monthlyTarget;
    final budgetSpend = regularSpent ?? currentSpent;
    final occasionalSpent =
        plannedOccasionalSpent + unexpectedOccasionalSpent;
    final hasBudget = target != null && target.isFinite && target >= 0;
    // Everything on this card is shown in whole dollars, and derived figures
    // (remaining, daily allowance, outcome) are computed from the rounded
    // numbers so they add up on a calculator.
    final targetWhole = target != null && target.isFinite
        ? target.roundToDouble()
        : null;
    final budgetRemaining = (targetWhole ?? 0) - budgetSpend.roundToDouble();
    final overBudget = hasBudget && budgetRemaining < 0;
    final dailyAllowance = hasBudget && !overBudget && daysRemaining > 0
        ? budgetRemaining / daysRemaining
        : null;
    final percentLeft = target != null && target > 0
        ? ((target - budgetSpend) / target * 100).clamp(0, 100).toDouble()
        : 0.0;
    final budgetRemainingProgress = percentLeft / 100;
    // Past months are shown as a finished result rather than a live budget.
    final outcome = !isCurrentMonth && target != null && hasBudget
        ? _BudgetOutcome.from(
            target: target,
            spent: budgetSpend,
            currencySymbol: currencySymbol,
          )
        : null;
    final outcomeColor = outcome?.color(theme);

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (availableMonths.length > 1 && onMonthSelected != null) ...[
              MonthSelector(
                selectedMonth: month,
                months: availableMonths,
                onSelected: onMonthSelected!,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatMonthHeading(month, now: currentDate),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'View this month’s spending breakdown',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCalendarPressed,
                  icon: const Icon(Icons.calendar_month),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // The whole total block is the tap target (not just the number),
            // with a chevron + hint so it reads as tappable.
            InkWell(
              key: const ValueKey('monthly-breakdown-tap-target'),
              onTap: onCalendarPressed,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total actual spending',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatAmount(currentSpent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: colorScheme.primary),
                      ],
                    ),
                    Text(
                      'Tap to see spending by category',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isCurrentMonth && rolloverRecap != null) ...[
              const SizedBox(height: 10),
              _RolloverRecapBanner(
                recap: rolloverRecap!,
                currencySymbol: currencySymbol,
              ),
            ],
            const SizedBox(height: 6),
            _ExpenseTypeBreakdown(
              actual: currentSpent,
              regular: budgetSpend,
              occasional: occasionalSpent,
              currencySymbol: currencySymbol,
            ),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('monthly-budget-summary'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BudgetMetric(
                          label: 'Monthly Budget',
                          value: hasBudget
                              ? formatWholeCurrency(target, currencySymbol)
                              : 'Not set',
                          trailing: Semantics(
                            button: true,
                            label: hasBudget
                                ? 'Edit monthly budget'
                                : 'Set monthly budget',
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onSetTargetPressed,
                                child: Tooltip(
                                  message: hasBudget
                                      ? 'Edit monthly budget'
                                      : 'Set monthly budget',
                                  child: Icon(
                                    hasBudget
                                        ? Icons.edit_outlined
                                        : Icons.add_circle_outline,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isCurrentMonth
                                  ? 'Budget remaining'
                                  : 'Budget outcome',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              key: const ValueKey('budget-remaining-value'),
                              !isCurrentMonth
                                  ? (outcome?.text ?? 'No budget recorded')
                                  : !hasBudget
                                  ? 'Set a monthly budget'
                                  : overBudget
                                  ? 'Over budget by ${formatWholeCurrency(budgetRemaining.abs(), currencySymbol)}'
                                  : formatWholeCurrency(
                                      budgetRemaining,
                                      currencySymbol,
                                    ),
                              textAlign: TextAlign.right,
                              style: isCurrentMonth
                                  ? theme.textTheme.titleLarge?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    )
                                  : theme.textTheme.titleMedium?.copyWith(
                                      color:
                                          outcomeColor ??
                                          colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (target != null && target > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: budgetRemainingProgress,
                        minHeight: 4,
                        color: outcomeColor ?? colorScheme.primary,
                        backgroundColor: colorScheme.surface,
                      ),
                    ),
                    if (isCurrentMonth) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${percentLeft.round()}% of budget left',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (isCurrentMonth) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        key: const ValueKey('daily-allowance-pill'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _DailyAllowanceBadgeContent(
                          hasBudget: hasBudget,
                          overBudget: overBudget,
                          daysRemaining: daysRemaining,
                          dailyAllowance: dailyAllowance,
                          currencySymbol: currencySymbol,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isCurrentMonth &&
                suggestedBudget != null &&
                onSuggestedBudgetPressed != null) ...[
              const SizedBox(height: 10),
              InkWell(
                key: const ValueKey('suggested-budget-card'),
                onTap: onSuggestedBudgetPressed,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Suggested ${formatWholeCurrency(suggestedBudget!.amount, currencySymbol)} · tap to see the split',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    return formatWholeCurrency(amount, currencySymbol);
  }
}

enum _OutcomeKind { under, over, exact }

/// Result of a finished month against its budget.
class _BudgetOutcome {
  const _BudgetOutcome._(this.kind, this.text);

  final _OutcomeKind kind;
  final String text;

  factory _BudgetOutcome.from({
    required double target,
    required double spent,
    required String currencySymbol,
  }) {
    // Whole-dollar comparison: "exactly on budget" means equal once rounded.
    final targetWhole = target.round();
    final difference = targetWhole - spent.round();
    if (difference == 0) {
      return const _BudgetOutcome._(_OutcomeKind.exact, 'Exactly on budget');
    }
    final amount = formatWholeCurrency(difference.abs().toDouble(), currencySymbol);
    final percent = targetWhole > 0
        ? ' (${_formatPercent(difference.abs() / targetWhole * 100)})'
        : '';
    return difference > 0
        ? _BudgetOutcome._(_OutcomeKind.under, 'Under budget by $amount$percent')
        : _BudgetOutcome._(_OutcomeKind.over, 'Over budget by $amount$percent');
  }

  static String _formatPercent(double percent) =>
      percent > 0 && percent < 1 ? '<1%' : '${percent.round()}%';

  /// Dark green / muted red / neutral, tuned for contrast in each theme.
  Color color(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return switch (kind) {
      _OutcomeKind.under =>
        isDark ? const Color(0xFF66BB6A) : const Color(0xFF1B5E20),
      _OutcomeKind.over =>
        isDark ? const Color(0xFFE08A8A) : const Color(0xFFA64545),
      _OutcomeKind.exact => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _BudgetMetric extends StatelessWidget {
  const _BudgetMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool alignEnd;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                value,
                textAlign: alignEnd ? TextAlign.right : TextAlign.left,
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

class _DailyAllowanceBadgeContent extends StatelessWidget {
  const _DailyAllowanceBadgeContent({
    required this.hasBudget,
    required this.overBudget,
    required this.daysRemaining,
    required this.dailyAllowance,
    required this.currencySymbol,
  });

  final bool hasBudget;
  final bool overBudget;
  final int daysRemaining;
  final double? dailyAllowance;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final amountStyle = TextStyle(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
    );

    final status = !hasBudget
        ? 'Set a monthly budget'
        : overBudget
        ? 'Not available while over budget'
        : daysRemaining <= 0
        ? 'Month ended'
        : null;
    final amount = dailyAllowance == null
        ? null
        : formatWholeCurrency(dailyAllowance!.roundToDouble(), currencySymbol);
    final daysText = daysRemaining == 1
        ? '1 day left'
        : '$daysRemaining days left';

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Daily Allowance '),
            if (status != null)
              TextSpan(text: status)
            else ...[
              TextSpan(text: amount, style: amountStyle),
              TextSpan(text: ' · $daysText'),
            ],
          ],
        ),
        maxLines: 1,
        softWrap: false,
        style: mutedStyle,
      ),
    );
  }
}

class _ExpenseTypeBreakdown extends StatelessWidget {
  const _ExpenseTypeBreakdown({
    required this.actual,
    required this.regular,
    required this.occasional,
    required this.currencySymbol,
  });

  final double actual;
  final double regular;
  final double occasional;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _ExpenseTypeLabel(
          label: 'Actual',
          amount: actual,
          currencySymbol: currencySymbol,
          color: color,
        ),
        _ExpenseTypeLabel(
          label: 'Regular',
          amount: regular,
          currencySymbol: currencySymbol,
          color: color,
        ),
        _ExpenseTypeLabel(
          label: 'Occasional',
          amount: occasional,
          currencySymbol: currencySymbol,
          color: color,
        ),
      ],
    );
  }
}

class _ExpenseTypeLabel extends StatelessWidget {
  const _ExpenseTypeLabel({
    required this.label,
    required this.amount,
    required this.currencySymbol,
    required this.color,
  });

  final String label;
  final double amount;
  final String currencySymbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label ${formatWholeCurrency(amount, currencySymbol)}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }
}

class _RolloverRecapBanner extends StatelessWidget {
  const _RolloverRecapBanner({
    required this.recap,
    required this.currencySymbol,
  });

  final MonthlyRolloverRecap recap;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stayedUnderBudget = recap.stayedUnderBudget;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: stayedUnderBudget
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        stayedUnderBudget
            ? '🎉 Great job last month! You stayed under budget by '
                  '${formatWholeCurrency(recap.difference, currencySymbol)}.'
            : '⚠️ Last month finished over budget by '
                  '${formatWholeCurrency(recap.difference, currencySymbol)}. '
                  "Here's to a fresh start!",
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: stayedUnderBudget
              ? colorScheme.onSurface
              : colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}