import 'package:flutter/material.dart';

import '../models/spending_target.dart';
import '../services/spending_target_store.dart';
import 'spending_targets_screen.dart';
import '../models/expense_category.dart';
import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import '../services/spending_reduction_planner_service.dart';
import '../services/financial_baseline_service.dart';
import '../utils/currency_format.dart';

class SpendingReductionPlannerScreen extends StatefulWidget {
  const SpendingReductionPlannerScreen({
    super.key,
    required this.transactions,
    required this.lifestyleMappings,
    required this.categories,
    required this.currencySymbol,
    this.targetStore,
    this.onTargetsSaved,
    this.historyComplete = false,
    this.hasUnsavedClassifications = false,
    this.targetMappings,
    this.baselineAnalysis,
  });

  final List<Transaction> transactions;
  final List<FinancialBaselineMapping> lifestyleMappings;
  final List<ExpenseCategory> categories;
  final String currencySymbol;
  final SpendingTargetStore? targetStore;
  final Future<String> Function()? onTargetsSaved;
  final bool historyComplete;
  final bool hasUnsavedClassifications;
  final List<FinancialBaselineMapping>? targetMappings;
  final FinancialBaselineAnalysis? baselineAnalysis;

  @override
  State<SpendingReductionPlannerScreen> createState() =>
      _SpendingReductionPlannerScreenState();
}

class _SpendingReductionPlannerScreenState
    extends State<SpendingReductionPlannerScreen> {
  final SpendingReductionPlannerService _service =
      SpendingReductionPlannerService();
  final TextEditingController _searchController = TextEditingController();
  late final SpendingReductionPlannerAnalysis _analysis;
  SpendingReductionView _view = SpendingReductionView.category;
  final Map<String, int> _targets = {};
  SpendingReductionPlan? _cachedPlan;

  static const _percentages = [10, 25, 50, 75, 100];

  @override
  void initState() {
    super.initState();
    _analysis = _service.analyze(
      transactions: widget.transactions,
      lifestyleMappings: widget.lifestyleMappings,
      categories: widget.categories,
      baselineAnalysis: widget.baselineAnalysis,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setTarget(String key, int percentage) {
    setState(() {
      _cachedPlan = null;
      if (percentage <= 0) {
        _targets.remove(key);
      } else {
        _targets[key] = percentage;
      }
    });
  }

  SpendingReductionPlan get _plan =>
      _cachedPlan ??= _analysis.calculate(_targets);

  Future<void> _openTargets() async {
    final store = widget.targetStore;
    if (store == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpendingTargetsScreen(
          store: store,
          transactions: widget.transactions,
          mappings: widget.targetMappings ?? widget.lifestyleMappings,
          categories: widget.categories,
          currencySymbol: widget.currencySymbol,
          onSaved: widget.onTargetsSaved,
          historyComplete: widget.historyComplete,
        ),
      ),
    );
  }

  Future<void> _activate() async {
    final store = widget.targetStore;
    if (store == null || _targets.isEmpty) return;
    final now = DateTime.now();
    var immediately = false;
    final drafts = <SpendingTarget>[];
    for (final entry in _targets.entries) {
      final merchant = entry.key.startsWith('merchant:');
      final id = entry.key.substring(9);
      final m = _analysis.merchants.where((m) => m.key == id).firstOrNull;
      final c = _analysis.categories.where((c) => c.id == id).firstOrNull;
      if (merchant ? m == null : c == null) continue;
      drafts.add(
        SpendingTarget.activate(
          type: merchant
              ? SpendingTargetType.merchant
              : SpendingTargetType.category,
          scopeId: id,
          name: merchant ? m!.name : c!.name,
          average: merchant ? m!.monthlySpending : c!.monthlySpending,
          percentage: entry.value.toDouble(),
          effectiveDate: DateTime(now.year, now.month + 1),
        ),
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Activate Spending Targets'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in drafts)
                    Text(
                      '${t.name}: ${formatFullCurrency(t.monthlyAmount, widget.currencySymbol)} / month (${t.reductionPercentage.round()}% reduction)',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Default start: ${MaterialLocalizations.of(ctx).formatMediumDate(DateTime(now.year, now.month + 1))}',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start immediately'),
                    value: immediately,
                    onChanged: (v) =>
                        setDialogState(() => immediately = v ?? false),
                  ),
                  if (immediately)
                    const Text(
                      'This month’s existing eligible spending will count toward these targets.',
                    ),
                  const Text(
                    'Merchant and category progress can overlap. The combined planned reduction still counts each expense once.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm activation'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.save([
        for (final t in drafts)
          immediately
              ? t.revise(effectiveDate: DateTime(now.year, now.month, now.day))
              : t,
      ]);
      final message =
          await widget.onTargetsSaved?.call() ??
          'Spending targets activated on this device, awaiting sync.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'View targets',
            onPressed: _openTargets,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not activate targets: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final plan = _plan;
    final query = _searchController.text.trim().toLowerCase();
    final categories = _analysis.categories
        .where((category) {
          return query.isEmpty || category.name.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final merchants = _analysis.merchants
        .where((merchant) {
          return query.isEmpty ||
              merchant.name.toLowerCase().contains(query) ||
              merchant.lifestyleGroup.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Your Spending Cuts'),
        actions: [
          if (widget.targetStore != null)
            IconButton(
              tooltip: 'Spending Targets',
              onPressed: _openTargets,
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
        leading: IconButton(
          tooltip: 'Close planner',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          _summaryCard(plan, colors),
          if (widget.targetStore != null)
            TextButton(
              onPressed: _targets.isEmpty || widget.hasUnsavedClassifications
                  ? null
                  : _activate,
              child: const Text('Activate Spending Targets'),
            ),
          if (widget.hasUnsavedClassifications && widget.targetStore != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Save classification changes before activating targets.',
              ),
            ),
          Expanded(
            child: CustomScrollView(
              key: const ValueKey('reduction-planner-scroll'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SegmentedButton<SpendingReductionView>(
                      key: const ValueKey('reduction-view-selector'),
                      segments: const [
                        ButtonSegment(
                          value: SpendingReductionView.category,
                          label: Text('By Category'),
                          icon: Icon(Icons.category_outlined),
                        ),
                        ButtonSegment(
                          value: SpendingReductionView.merchant,
                          label: Text('By Merchant'),
                          icon: Icon(Icons.storefront_outlined),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (selected) => setState(() {
                        _view = selected.single;
                        _searchController.clear();
                      }),
                    ),
                  ),
                ),
                if (_view == SpendingReductionView.category &&
                    _analysis.hasUncategorizedSpending)
                  SliverToBoxAdapter(
                    child: Container(
                      key: const ValueKey('uncategorized-category-warning'),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Some adjustable spending has no expense category yet. Merchant planning remains available.',
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      key: const ValueKey('reduction-search'),
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: _view == SpendingReductionView.category
                            ? 'Search categories'
                            : 'Search merchants',
                        border: const OutlineInputBorder(),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 4)),
                _buildSpendingRows(categories, merchants),
                SliverToBoxAdapter(child: _planBreakdown(plan, colors)),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(SpendingReductionPlan plan, ColorScheme colors) => Card(
    key: const ValueKey('reduction-plan-summary'),
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    color: colors.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Planned Monthly Reduction'),
                Text(
                  '${formatFullCurrency(plan.monthlyReduction, widget.currencySymbol)} / month',
                  key: const ValueKey('planned-monthly-reduction'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Annualized Potential · ${formatFullCurrency(plan.annualizedPotential, widget.currencySymbol)} / year if maintained',
                  key: const ValueKey('planned-annualized-potential'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${plan.targetCount} reduction target${plan.targetCount == 1 ? '' : 's'} selected · projected, not achieved savings',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSpendingRows(
    List<ReductionCategoryOption> categories,
    List<ReductionMerchantOption> merchants,
  ) {
    final itemCount = _view == SpendingReductionView.category
        ? categories.length + (_analysis.hasUncategorizedSpending ? 1 : 0)
        : merchants.length;
    if (itemCount == 0) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            _view == SpendingReductionView.category
                ? 'No adjustable category spending found.'
                : 'No adjustable merchants found.',
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final Widget row;
          if (_view == SpendingReductionView.category) {
            if (index == categories.length) {
              row = ListTile(
                key: const ValueKey('reduction-uncategorized-row'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Uncategorised / Other'),
                subtitle: Text(
                  'Category not yet known · ${formatFullCurrency(_analysis.uncategorizedMonthlySpending, widget.currencySymbol)} / mo · ${_analysis.uncategorizedTransactionCount} transactions · no category target',
                ),
              );
            } else {
              final category = categories[index];
              row = _spendingRow(
                key: ValueKey('reduction-category-${category.id}'),
                title: category.name,
                subtitle:
                    '${formatFullCurrency(category.monthlySpending, widget.currencySymbol)} / mo eligible · ${category.transactionCount} transactions',
                targetKey: 'category:${category.id}',
              );
            }
          } else {
            final merchant = merchants[index];
            row = _spendingRow(
              key: ValueKey('reduction-merchant-${merchant.key}'),
              title: merchant.name,
              subtitle:
                  '${merchant.lifestyleGroup} · ${formatFullCurrency(merchant.monthlySpending, widget.currencySymbol)} / mo · ${merchant.transactionCount} transactions',
              targetKey: 'merchant:${merchant.key}',
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [row, const Divider(height: 1)],
          );
        }, childCount: itemCount),
      ),
    );
  }

  Widget _spendingRow({
    required Key key,
    required String title,
    required String subtitle,
    required String targetKey,
  }) => ListTile(
    key: key,
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: _targetSelector(targetKey),
  );

  Widget _targetSelector(String key) {
    final current = _targets[key];
    if (current == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: ValueKey('target-selector-$key'),
            onPressed: () => _setTarget(key, 25),
            child: const Text('Set 25%'),
          ),
          PopupMenuButton<int>(
            key: ValueKey('target-options-$key'),
            tooltip: 'Choose a different reduction target',
            onSelected: (percentage) => _setTarget(key, percentage),
            itemBuilder: (context) => [
              for (final percentage in _percentages)
                PopupMenuItem(
                  value: percentage,
                  child: Text('Reduce $percentage%'),
                ),
            ],
            icon: const Icon(Icons.arrow_drop_down),
          ),
        ],
      );
    }
    return DropdownButton<int>(
      key: ValueKey('target-selector-$key'),
      value: current,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [
        const DropdownMenuItem(value: 0, child: Text('No target')),
        for (final percentage in _percentages)
          DropdownMenuItem(value: percentage, child: Text('$percentage%')),
      ],
      onChanged: (value) {
        if (value != null) _setTarget(key, value);
      },
    );
  }

  Widget _planBreakdown(SpendingReductionPlan plan, ColorScheme colors) => Card(
    margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
    child: ExpansionTile(
      key: const ValueKey('your-reduction-plan-expansion'),
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(
        'Your Reduction Plan',
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${plan.targetCount} selected · ${formatFullCurrency(plan.monthlyReduction, widget.currencySymbol)} / mo projected',
      ),
      children: [
        if (plan.impacts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Choose reduction targets to build a what-if plan.'),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final impact in plan.impacts)
                  ListTile(
                    key: ValueKey('plan-impact-${impact.key}'),
                    dense: true,
                    title: Text(
                      '${impact.name} · ${impact.isMerchant ? 'Merchant' : 'Category'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${impact.percentage}% reduction${impact.transactionCount == 1 ? ' · historical activity may be one-time' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatFullCurrency(
                            impact.monthlyReduction,
                            widget.currencySymbol,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('remove-plan-target-${impact.key}'),
                          tooltip: 'Remove target',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setTarget(impact.key, 0),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (plan.impacts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total · ${formatFullCurrency(plan.monthlyReduction, widget.currencySymbol)} / month',
                key: const ValueKey('plan-breakdown-total'),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    ),
  );
}
