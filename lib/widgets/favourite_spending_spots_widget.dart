import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/favourite_spending_spots_service.dart';
import '../utils/currency_format.dart';

class FavouriteSpendingSpotsWidget extends StatefulWidget {
  const FavouriteSpendingSpotsWidget({
    required this.transactions,
    required this.currencySymbol,
    this.now,
    super.key,
  });

  final List<Transaction> transactions;
  final String currencySymbol;
  final DateTime? now;

  @override
  State<FavouriteSpendingSpotsWidget> createState() =>
      _FavouriteSpendingSpotsWidgetState();
}

class _FavouriteSpendingSpotsWidgetState
    extends State<FavouriteSpendingSpotsWidget> {
  final FavouriteSpendingSpotsService _service =
      FavouriteSpendingSpotsService();
  late FavouriteSpendingSpotsData _data;
  SpendingSpotFilter _filter = SpendingSpotFilter.actual;

  @override
  void initState() {
    super.initState();
    _data = _calculate();
  }

  @override
  void didUpdateWidget(covariant FavouriteSpendingSpotsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.transactions, widget.transactions) ||
        oldWidget.now != widget.now) {
      _data = _calculate();
    }
  }

  FavouriteSpendingSpotsData _calculate() {
    return _service.calculate(
      transactions: widget.transactions,
      now: widget.now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = _data.spotsFor(_filter).take(5).toList(growable: false);
    final periodLabel = _data.completedMonths == 6
        ? 'Last 6 completed months'
        : _data.completedMonths == 1
        ? '1 completed month available'
        : '${_data.completedMonths} completed months available';

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Favourite Spending Spots',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The places where you spend the most.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(periodLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            SegmentedButton<SpendingSpotFilter>(
              key: const ValueKey('favourite-spending-filter'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: SpendingSpotFilter.actual,
                  label: Text('Actual'),
                ),
                ButtonSegment(
                  value: SpendingSpotFilter.regular,
                  label: Text('Regular'),
                ),
                ButtonSegment(
                  value: SpendingSpotFilter.occasional,
                  label: Text('Occasional'),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) =>
                  setState(() => _filter = selection.first),
            ),
            if (spots.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _data.completedMonths == 0
                      ? 'Complete a month of expense history to see your spending spots.'
                      : 'No net spending spots found for this selection.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else ...[
              const SizedBox(height: 8),
              for (var index = 0; index < spots.length; index++)
                _SpendingSpotTile(
                  rank: index + 1,
                  spot: spots[index],
                  currencySymbol: widget.currencySymbol,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SpendingSpotDetailScreen(
                        spot: spots[index],
                        currencySymbol: widget.currencySymbol,
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
}

class _SpendingSpotTile extends StatelessWidget {
  const _SpendingSpotTile({
    required this.rank,
    required this.spot,
    required this.currencySymbol,
    required this.onTap,
  });

  final int rank;
  final FavouriteSpendingSpot spot;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = spot.name.isEmpty ? 'Unspecified spending spot' : spot.name;
    final metrics =
        '${formatFullCurrency(spot.total, currencySymbol)} total  ·  '
        '${formatFullCurrency(spot.averageMonthly, currencySymbol)}/mo';
    return Semantics(
      button: true,
      label: '$rank. $name. $metrics',
      child: InkWell(
        key: ValueKey('favourite-spending-spot-${spot.key}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                child: Text('$rank', style: theme.textTheme.labelMedium),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Tooltip(
                  message:
                      'Total: ${formatFullCurrency(spot.total, currencySymbol)} · '
                      'Average: ${formatFullCurrency(spot.averageMonthly, currencySymbol)}/month',
                  child: Text(
                    metrics,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class SpendingSpotDetailScreen extends StatelessWidget {
  const SpendingSpotDetailScreen({
    required this.spot,
    required this.currencySymbol,
    super.key,
  });

  final FavouriteSpendingSpot spot;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final transactions = [...spot.transactions]
      ..sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
    return Scaffold(
      appBar: AppBar(title: Text(spot.name)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: transactions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = transactions[index];
          final transaction = item.transaction;
          final date = transaction.date;
          final dateText =
              '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';
          final amountLabel = item.netAmount < 0
              ? '-${formatFullCurrency(item.netAmount.abs(), currencySymbol)}'
              : formatFullCurrency(item.netAmount, currencySymbol);
          return ListTile(
            key: ValueKey(
              'spending-spot-transaction-${transaction.id ?? transaction.sheetRow ?? index}',
            ),
            contentPadding: EdgeInsets.zero,
            title: Text(
              transaction.description.isEmpty
                  ? 'No description'
                  : transaction.description,
            ),
            subtitle: Text(
              '$dateText · ${transaction.category} · '
              '${transaction.expenseType.sheetValue}',
            ),
            trailing: Text(
              amountLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        },
      ),
    );
  }
}
