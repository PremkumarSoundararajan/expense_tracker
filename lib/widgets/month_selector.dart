import 'package:flutter/material.dart';

import '../utils/transaction_period_format.dart';

class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.selectedMonth,
    required this.months,
    required this.onSelected,
  });

  final DateTime selectedMonth;
  final List<DateTime> months;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    if (months.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        key: const ValueKey('hero-month-selector'),
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final month = months[index];
          final selected = isSameMonth(month, selectedMonth);
          return ChoiceChip(
            label: Text(formatMonthYearShort(month)),
            selected: selected,
            onSelected: (_) => onSelected(monthStart(month)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }
}
