import 'package:flutter/material.dart';

import '../utils/transaction_period_format.dart';

/// Calendar-month navigation, including gaps in recorded history.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.selectedMonth,
    required this.months,
    required this.onSelected,
    this.now,
  });
  final DateTime selectedMonth;
  final List<DateTime> months;
  final ValueChanged<DateTime> onSelected;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final current = monthStart(now ?? DateTime.now());
    final selected = monthStart(selectedMonth);
    final supported = [
      ...months.where((m) => !m.isAfter(current)),
      selected,
      current,
    ]..sort();
    final first = monthStart(supported.first);
    Future<void> pickMonth() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: selected.isAfter(current) ? current : selected,
        firstDate: first,
        lastDate: DateTime(current.year, current.month + 1, 0),
        initialDatePickerMode: DatePickerMode.year,
        helpText: 'Choose a month',
      );
      if (picked != null) onSelected(monthStart(picked));
    }

    return Row(
      key: const ValueKey('hero-month-selector'),
      children: [
        IconButton(
          tooltip: 'Previous month',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 44),
          onPressed: selected.isAfter(first)
              ? () => onSelected(DateTime(selected.year, selected.month - 1))
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
            ),
            onPressed: pickMonth,
            child: Text(
              MaterialLocalizations.of(context).formatMonthYear(selected),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 44),
          onPressed: selected.isBefore(current)
              ? () => onSelected(nextMonthStart(selected))
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'Choose month',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 44),
          onPressed: pickMonth,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ],
    );
  }
}
