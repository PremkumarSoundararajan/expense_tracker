import 'package:flutter/material.dart';

import '../services/monthly_rollover_service.dart';
import '../services/budget_comparison.dart';
import '../services/suggested_budget_service.dart';
import '../utils/currency_format.dart';
import '../utils/transaction_period_format.dart';
import 'month_selector.dart';

class MonthlyBudgetCard extends StatelessWidget {
  const MonthlyBudgetCard({
    super.key,
    required this.currentSpent,
    this.regularSpent,
    this.spending,
    this.onReviewUnclassified,
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
    this.showHeading = true,
  });

  final double currentSpent;
  final bool showHeading;
  final BudgetSpending? spending;
  final double? regularSpent;
  final VoidCallback? onReviewUnclassified;
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
    final colors = theme.colorScheme;
    final date = now ?? DateTime.now();
    final month = selectedMonth ?? monthStart(date);
    final current = isSameMonth(month, date);
    final amounts =
        spending ??
        BudgetSpending.fromAmounts(
          total: currentSpent,
          regular: regularSpent ?? currentSpent,
          planned: plannedOccasionalSpent,
          unexpected: unexpectedOccasionalSpent,
        );
    final target = monthlyTarget;
    final hasBudget = target != null && target.isFinite && target >= 0;
    final result = hasBudget ? amounts.recordedOutcome(target) : null;
    final remaining = hasBudget ? amounts.recordedRemaining(target) : 0.0;
    // The hero shows actual spending; only budget-relevant spending fills the bar.
    final progressRatio = !hasBudget
        ? 0.0
        : target > 0
        ? (amounts.budgetRelevant / target).clamp(0.0, 1.0)
        : amounts.budgetRelevant > 0
        ? 1.0
        : 0.0;
    final days =
        DateUtils.getDaysInMonth(month.year, month.month) - date.day + 1;
    final daily = current && hasBudget
        ? ((remaining.clamp(0, double.infinity) / days * 100).floor() / 100)
        : 0.0;
    String money(double value) => formatFullCurrency(value, currencySymbol);
    String whole(double value) => formatWholeCurrency(value, currencySymbol);
    final status = switch (result) {
      BudgetOutcome.over => 'Over budget',
      BudgetOutcome.exact => 'Exactly on budget',
      BudgetOutcome.within => 'Within budget',
      _ => 'No budget set',
    };
    final statusColor = result == BudgetOutcome.over
        ? colors.error
        : colors.primary;
    final heading = MaterialLocalizations.of(context).formatMonthYear(month);
    Widget row(String label, String value, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.w700 : null,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.w700 : null,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
    void details() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 680),
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Budget details — $heading',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close budget details',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                row('Total actual spending', money(amounts.total)),
                row(
                  'Unexpected expenses excluded',
                  amounts.unexpected > 0
                      ? '-${money(amounts.unexpected)}'
                      : money(-amounts.unexpected),
                ),
                const Divider(),
                row(
                  'Counted toward budget',
                  money(amounts.budgetRelevant),
                  bold: true,
                ),
                row('Monthly budget', hasBudget ? money(target) : 'Not set'),
                if (hasBudget)
                  row(
                    remaining < 0 ? 'Over budget' : 'Remaining',
                    money(remaining.abs()),
                    bold: true,
                    color: statusColor,
                  ),
                if (hasBudget && current)
                  row('Daily allowance ($days days left)', money(daily)),
                if (amounts.hasUnknown)
                  TextButton(
                    key: const ValueKey('monthly-budget-coverage'),
                    onPressed: onReviewUnclassified == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            onReviewUnclassified!();
                          },
                    child: Text(
                      'Includes ${money(amounts.unknown)} unclassified · Review',
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onSetTargetPressed();
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(hasBudget ? 'Edit budget' : 'Set budget'),
                ),
                if (current &&
                    suggestedBudget != null &&
                    onSuggestedBudgetPressed != null)
                  TextButton(
                    key: const ValueKey('suggested-budget-card'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onSuggestedBudgetPressed!();
                    },
                    child: Text(
                      'Suggested ${money(suggestedBudget!.amount)} · View calculation',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final total = Semantics(
      button: true,
      label: 'View spending by category',
      child: InkWell(
        key: const ValueKey('monthly-breakdown-tap-target'),
        onTap: onCalendarPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              whole(amounts.total),
              maxLines: 1,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: 38,
                height: 1.05,
                letterSpacing: -.5,
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeading)
            if (onMonthSelected != null)
              MonthSelector(
                selectedMonth: month,
                months: availableMonths,
                now: date,
                onSelected: onMonthSelected!,
              )
            else
              Text(heading, style: theme.textTheme.labelLarge),
          const SizedBox(height: 18),
          Row(
            key: const ValueKey('budget-kpi-row'),
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const ValueKey('actual-expense-label'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Actual expense',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    total,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      hasBudget
                          ? 'Budget: ${whole(target)}'
                          : 'Budget: Not set',
                      key: const ValueKey('budget-kpi-value'),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  status,
                  key: const ValueKey('budget-remaining-value'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasBudget) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      '${whole(remaining.abs())} ${remaining < 0 ? 'over' : 'left'}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasBudget) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 10,
              borderRadius: BorderRadius.circular(8),
              value: progressRatio,
              color: statusColor,
            ),
            if (!current && result == BudgetOutcome.within) ...[
              const SizedBox(height: 10),
              Text(
                'Great job! You stayed within your budget.',
                key: const ValueKey('past-budget-congratulations'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
            if (current &&
                rolloverRecap != null &&
                rolloverRecap!.stayedUnderBudget) ...[
              const SizedBox(height: 10),
              Text(
                rolloverRecap!.difference == 0
                    ? 'Last month finished on budget.'
                    : 'Great job last month! ${whole(rolloverRecap!.difference)} under budget.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              if (current && hasBudget)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: const ValueKey('daily-allowance-pill'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Can spend: ${money(daily)} / day',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 124),
                child: TextButton(
                  key: const ValueKey('monthly-budget-details'),
                  onPressed: details,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Budget details'),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
