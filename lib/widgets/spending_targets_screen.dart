import 'package:flutter/material.dart';

import '../models/spending_target.dart';
import '../models/transaction.dart';
import '../models/financial_baseline.dart';
import '../models/expense_category.dart';
import '../services/spending_target_service.dart';
import '../services/spending_target_store.dart';
import '../utils/currency_format.dart';

class SpendingTargetsScreen extends StatelessWidget {
  const SpendingTargetsScreen({
    super.key,
    required this.store,
    required this.transactions,
    required this.mappings,
    required this.categories,
    required this.currencySymbol,
    this.onSaved,
    this.historyComplete = false,
  });
  final SpendingTargetStore store;
  final List<Transaction> transactions;
  final List<FinancialBaselineMapping> mappings;
  final List<ExpenseCategory> categories;
  final String currencySymbol;
  final Future<String> Function()? onSaved;
  final bool historyComplete;

  Future<void> _save(BuildContext context, SpendingTarget target) async {
    try {
      await store.save([target]);
      final message =
          await onSaved?.call() ?? 'Saved on this device, awaiting sync.';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save target: $e')));
      }
    }
  }

  Future<void> _edit(BuildContext context, SpendingTarget target) async {
    var amountText = target.monthlyAmount.toStringAsFixed(2);
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    final start = target.effectiveDate.isAfter(nextMonth)
        ? target.effectiveDate
        : nextMonth;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${target.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Applies from ${MaterialLocalizations.of(ctx).formatMediumDate(start)}. This month’s definition stays in place.',
            ),
            TextFormField(
              initialValue: amountText,
              onChanged: (value) => amountText = value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monthly spending target',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountText);
              if (amount != null && amount.isFinite && amount >= 0) {
                Navigator.pop(ctx, amount);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      await _save(context, target.revise(effectiveDate: start, amount: result));
    }
  }

  Future<void> _deactivate(BuildContext context, SpendingTarget target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate ${target.name}?'),
        content: const Text(
          'Earlier target definitions remain available for historical comparisons.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Cancel scheduled revisions too, otherwise one could reactivate it later.
      await store.save([
        for (final t in store.targets.where(
          (t) =>
              t.scopeKey == target.scopeKey && t.effectiveDate.isAfter(today),
        ))
          t.revise(effectiveDate: t.effectiveDate, active: false),
        target.revise(effectiveDate: today, active: false),
      ]);
      final message =
          await onSaved?.call() ?? 'Deactivated locally, awaiting sync.';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spending Targets')),
    body: AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final service = SpendingTargetService();
        final usage = service.usage(
          targets: store.targets,
          transactions: transactions,
          mappings: mappings,
          categories: categories,
          asOf: now,
        );
        final future =
            store.targets
                .where((t) => t.active && t.effectiveDate.isAfter(now))
                .toList()
              ..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
        String money(double v) => formatFullCurrency(v, currencySymbol);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!historyComplete)
              const Text(
                'Based on locally available transactions. Usage may be incomplete until the ledger is refreshed.',
              ),
            if (store.hasPending)
              const Text(
                'Target changes are saved on this device and waiting to sync.',
              ),
            if (usage.isEmpty && future.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No active spending targets. Activate a reduction plan to begin.',
                ),
              ),
            for (final u in usage)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${u.target.name} · ${u.target.type == SpendingTargetType.merchant ? 'Merchant' : 'Category'}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${money(u.actual)} spent / ${money(u.target.monthlyAmount)} target',
                      ),
                      LinearProgressIndicator(
                        value: u.progress.clamp(0, 1).toDouble(),
                      ),
                      Text(
                        '${u.label} · ${money(u.remaining.abs())} ${u.remaining < 0 ? 'over target' : 'remaining'}',
                      ),
                      Text(
                        'Effective ${MaterialLocalizations.of(context).formatMediumDate(u.target.effectiveDate)}',
                      ),
                      if (u.needsReview)
                        const Text(
                          'Needs review: this scope includes unavailable or Essential spending. Only Potentially Flexible spending counts.',
                        ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => _edit(context, u.target),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () => _deactivate(context, u.target),
                            child: const Text('Deactivate'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            for (final t in future)
              Card(
                child: ListTile(
                  title: Text(t.name),
                  subtitle: Text(
                    '${money(t.monthlyAmount)} / month · starts ${MaterialLocalizations.of(context).formatMediumDate(t.effectiveDate)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => action == 'edit'
                        ? _edit(context, t)
                        : _deactivate(context, t),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'deactivate',
                        child: Text('Deactivate'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
