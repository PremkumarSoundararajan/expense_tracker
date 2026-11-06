import 'package:flutter/material.dart';

import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import '../services/financial_baseline_service.dart';
import '../services/merchant_normalizer.dart';
import '../services/merchant_discovery_service.dart';
import '../utils/currency_format.dart';

class FinancialBaselineScreen extends StatefulWidget {
  const FinancialBaselineScreen({
    super.key,
    required this.transactions,
    required this.initialMappings,
    required this.currencySymbol,
    required this.onMappingsSaved,
    this.initialDraft,
    this.onDraftChanged,
    this.onDraftCleared,
  });

  final List<Transaction> transactions;
  final List<FinancialBaselineMapping> initialMappings;
  final String currencySymbol;
  final Future<String?> Function(List<FinancialBaselineMapping>)
  onMappingsSaved;
  final FinancialBaselineDraft? initialDraft;
  final Future<void> Function(FinancialBaselineDraft)? onDraftChanged;
  final Future<void> Function()? onDraftCleared;

  @override
  State<FinancialBaselineScreen> createState() =>
      _FinancialBaselineScreenState();
}

class _FinancialBaselineScreenState extends State<FinancialBaselineScreen> {
  final FinancialBaselineService _service = FinancialBaselineService();
  final MerchantDiscoveryService _merchantDiscoveryService =
      MerchantDiscoveryService();
  final MerchantNormalizer _normalizer = const MerchantNormalizer();
  late final FinancialBaselineProvider _provider;
  late final List<DiscoveredMerchant> _merchants;
  late final Map<String, String> _merchantSearchIndex;
  late List<FinancialBaselineMapping> _mappings;
  late List<FinancialBaselineMapping> _committedMappings;
  _MerchantSort _merchantSort = _MerchantSort.highestSpending;
  bool _isSaving = false;
  bool _draftRestored = false;
  final List<String> _draftConflictMerchants = [];

  @override
  void initState() {
    super.initState();
    _committedMappings = List.of(widget.initialMappings);
    final restored = widget.initialDraft;
    _draftRestored = restored != null;
    final initial = restored == null
        ? widget.initialMappings
        : _reconcileDraft(widget.initialMappings, restored);
    _provider = FinancialBaselineProvider(
      transactions: widget.transactions,
      mappings: initial,
      service: _service,
    );
    _mappings = _provider.mappings;
    _merchants = _merchantDiscoveryService.discover(_provider.transactions);
    final descriptions = <String, List<String>>{};
    for (final transaction in _provider.transactions) {
      final fingerprint = _normalizedFingerprint(transaction.description);
      if (fingerprint.isEmpty) continue;
      descriptions
          .putIfAbsent(fingerprint, () => [])
          .add(transaction.description.toLowerCase());
    }
    _merchantSearchIndex = {
      for (final entry in descriptions.entries)
        entry.key: entry.value.join(' '),
    };
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  String _normalizedFingerprint(String value) =>
      _normalizer.normalize(value).trim().toLowerCase();

  String _stateKey(DiscoveredMerchant merchant) =>
      _normalizedFingerprint(merchant.merchantFingerprint);

  List<FinancialBaselineMapping> _reconcileDraft(
    List<FinancialBaselineMapping> latest,
    FinancialBaselineDraft draft,
  ) {
    final base = {
      for (final m in draft.baseMappings)
        _normalizedFingerprint(m.merchantFingerprint): m,
    };
    final desired = {
      for (final m in draft.draftMappings)
        _normalizedFingerprint(m.merchantFingerprint): m,
    };
    final merged = {
      for (final m in latest) _normalizedFingerprint(m.merchantFingerprint): m,
    };
    final keys = {...base.keys, ...desired.keys};
    for (final key in keys) {
      final before = base[key]?.group;
      final wanted = desired[key]?.group;
      if (before == wanted) continue;
      final remote = merged[key]?.group;
      if (remote == before || remote == wanted) {
        if (wanted == null) {
          merged.remove(key);
        } else {
          merged[key] = desired[key]!;
        }
      } else {
        final name =
            desired[key]?.merchantFingerprint ?? base[key]?.merchantFingerprint;
        if (name != null) _draftConflictMerchants.add(name);
      }
    }
    return merged.values.toList(growable: false);
  }

  int get _changedCount {
    final committed = {
      for (final m in _committedMappings)
        _normalizedFingerprint(m.merchantFingerprint): m.group,
    };
    final draft = {
      for (final m in _mappings)
        _normalizedFingerprint(m.merchantFingerprint): m.group,
    };
    return {
      ...committed.keys,
      ...draft.keys,
    }.where((key) => committed[key] != draft[key]).length;
  }

  List<DiscoveredMerchant> get _unassignedMerchants {
    final assigned = _mappings
        .map((m) => _normalizedFingerprint(m.merchantFingerprint))
        .toSet();
    final values = _merchants
        .where(
          (m) =>
              !assigned.contains(_normalizedFingerprint(m.merchantFingerprint)),
        )
        .toList();
    values.sort((a, b) {
      final comparison = switch (_merchantSort) {
        _MerchantSort.highestSpending => b.totalAmount.compareTo(a.totalAmount),
        _MerchantSort.mostTransactions => b.occurrenceCount.compareTo(
          a.occurrenceCount,
        ),
        _MerchantSort.merchantName =>
          a.merchantFingerprint.toLowerCase().compareTo(
            b.merchantFingerprint.toLowerCase(),
          ),
      };
      return comparison != 0
          ? comparison
          : a.merchantFingerprint.compareTo(b.merchantFingerprint);
    });
    return values;
  }

  Future<void> _chooseGroup(List<DiscoveredMerchant> merchants) async {
    final group = await showModalBottomSheet<BaselineGroup>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              merchants.length == 1
                  ? 'Assign ${merchants.single.merchantFingerprint}'
                  : 'Assign ${merchants.length} merchants',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final group in BaselineGroup.values)
              ListTile(
                key: ValueKey('assign-to-group-${group.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(_groupIcon(group)),
                title: Text(group.label),
                onTap: () => Navigator.pop(context, group),
              ),
          ],
        ),
      ),
    );
    if (group == null || !mounted) return;
    await _assignMerchants(merchants, group);
  }

  Future<void> _assignMerchants(
    List<DiscoveredMerchant> merchants,
    BaselineGroup group,
  ) async {
    final assigned = {
      for (final merchant in merchants)
        _normalizedFingerprint(merchant.merchantFingerprint):
            merchant.merchantFingerprint,
    };
    final updated = _mappings
        .where(
          (mapping) => !assigned.containsKey(
            _normalizedFingerprint(mapping.merchantFingerprint),
          ),
        )
        .toList();
    updated.addAll(
      assigned.values.map(
        (fingerprint) => FinancialBaselineMapping(
          merchantFingerprint: fingerprint,
          group: group,
        ),
      ),
    );
    await _saveMappings(updated, showSuccessMessage: false);
  }

  Future<void> _unassignMerchant(FinancialBaselineMapping mapping) async {
    final updated = _mappings.where((candidate) => candidate.id != mapping.id);
    await _saveMappings(updated, showSuccessMessage: false);
  }

  Future<bool> _saveMappings(
    Iterable<FinancialBaselineMapping> mappings, {
    bool showSuccessMessage = true,
  }) async {
    _provider.updateMappings(mappings);
    setState(() {
      _mappings = _provider.mappings;
    });
    try {
      await widget.onDraftChanged?.call(
        FinancialBaselineDraft(
          baseMappings: List.unmodifiable(_committedMappings),
          draftMappings: List.unmodifiable(_mappings),
        ),
      );
      if (mounted && showSuccessMessage) {
        _showMessage('Draft updated. Save changes when you are ready.');
      }
      return true;
    } catch (error) {
      if (mounted) {
        _showMessage('Could not save the local draft: $error');
      }
      return false;
    }
  }

  Future<void> _commitDraft() async {
    if (_changedCount == 0 || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final message = await widget.onMappingsSaved(
        List.unmodifiable(_mappings),
      );
      _committedMappings = List.of(_mappings);
      await widget.onDraftCleared?.call();
      if (mounted) setState(() => _draftRestored = false);
      if (mounted) _showMessage(message ?? 'Baseline changes saved.');
    } catch (error) {
      if (mounted) _showMessage('Changes remain in your local draft: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _discardDraft() async {
    _provider.updateMappings(_committedMappings);
    await widget.onDraftCleared?.call();
    if (!mounted) return;
    setState(() {
      _mappings = _provider.mappings;
      _draftRestored = false;
    });
  }

  Widget _buildOrganizer(ColorScheme colors) {
    final unassigned = _unassignedMerchants;
    return Container(
      key: const ValueKey('organize-your-spending'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organize Your Spending',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            'Assign merchants to lifestyle groups to understand what you need, what you’re committed to, and where you can reduce spending.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_draftConflictMerchants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Some restored draft changes conflict with newer saved assignments. The saved assignments were kept for ${_draftConflictMerchants.join(', ')}. Reassign them here if you still want to change them.',
                key: const ValueKey('baseline-draft-conflicts'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.error),
              ),
            ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in BaselineGroup.values)
                    SizedBox(
                      width: width,
                      child: _buildGroupCard(
                        group,
                        _provider.summary.metrics[group]!,
                        colors,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Merchants to Organize',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${unassigned.length} remaining',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 5),
          DropdownButtonFormField<_MerchantSort>(
            key: const ValueKey('merchant-sort-order'),
            initialValue: _merchantSort,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Sort merchants',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(
                value: _MerchantSort.highestSpending,
                child: Text('Highest total spending'),
              ),
              DropdownMenuItem(
                value: _MerchantSort.mostTransactions,
                child: Text('Most transactions'),
              ),
              DropdownMenuItem(
                value: _MerchantSort.merchantName,
                child: Text('Merchant name'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _merchantSort = value);
            },
          ),
          const SizedBox(height: 5),
          if (unassigned.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('All discovered merchants are assigned.'),
            )
          else
            Column(
              key: const ValueKey('unassigned-merchant-list'),
              children: [
                for (final merchant in unassigned.take(20))
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: ValueKey('unassigned-${_stateKey(merchant)}'),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(
                        merchant.merchantFingerprint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatFullCurrency(merchant.totalAmount, widget.currencySymbol)} total · ${merchant.occurrenceCount} transactions · ${formatFullCurrency(merchant.averageAmount, widget.currencySymbol)} average',
                      ),
                      trailing: Icon(
                        Icons.add_circle_outline,
                        color: colors.primary,
                      ),
                      onTap: _isSaving ? null : () => _chooseGroup([merchant]),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(
    BaselineGroup group,
    BaselineGroupMetrics metrics,
    ColorScheme colors,
  ) {
    final mappings = _mappings
        .where((mapping) => mapping.group == group)
        .toList(growable: false);
    final available = _unassignedMerchants;
    final tint = _groupColor(group);
    final description = switch (group) {
      BaselineGroup.essential =>
        'Must maintain · basic groceries, utilities, transport, healthcare',
      BaselineGroup.committed =>
        'Obligations · housing, loans, contracts, insurance',
      BaselineGroup.discretionary =>
        'Easiest to cut · optional shopping, entertainment, subscriptions',
      BaselineGroup.potentiallyFlexible =>
        'Optimize · dining, phone or internet, travel, vehicle costs',
    };
    return Container(
      key: ValueKey('baseline-group-${group.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_groupIcon(group), color: tint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  group.label,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800, color: tint),
                ),
              ),
              Text(
                '${formatFullCurrency(metrics.monthlyAverage, widget.currencySymbol)} / mo',
                key: ValueKey('baseline-group-average-${group.name}'),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          Text(
            '${mappings.length} merchants assigned',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 5),
          Autocomplete<DiscoveredMerchant>(
            key: ValueKey('group-autocomplete-${group.name}'),
            displayStringForOption: (merchant) => merchant.merchantFingerprint,
            optionsBuilder: (value) {
              final query = _normalizedFingerprint(value.text);
              if (query.isEmpty) {
                return const Iterable<DiscoveredMerchant>.empty();
              }
              return available
                  .where(
                    (merchant) =>
                        _normalizedFingerprint(merchant.merchantFingerprint)
                            .contains(query) ||
                        (_merchantSearchIndex[_stateKey(merchant)]?.contains(
                              query,
                            ) ??
                            false),
                  )
                  .take(12);
            },
            onSelected: (merchant) => _assignMerchants([merchant], group),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 5,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    maxWidth: 420,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final merchant in options)
                        ListTile(
                          key: ValueKey(
                            'autocomplete-option-${_stateKey(merchant)}',
                          ),
                          dense: true,
                          title: Text(merchant.merchantFingerprint),
                          subtitle: Text(
                            '${merchant.occurrenceCount} transactions · ${formatFullCurrency(merchant.totalAmount, widget.currencySymbol)}',
                          ),
                          onTap: () => onSelected(merchant),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) => TextField(
                  key: ValueKey('group-search-${group.name}'),
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Add merchant',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 31, top: 2),
            child: Text(
              '${formatFullCurrency(metrics.annualizedAmount, widget.currencySymbol)} / yr normalized',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 31, top: 3),
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (mappings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 31, top: 7),
              child: Text(
                'No merchants assigned',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 27, top: 4),
              child: Wrap(
                spacing: 3,
                runSpacing: 0,
                children: [
                  for (final mapping in mappings)
                    InputChip(
                      key: ValueKey(
                        'mapped-${group.name}-${mapping.merchantFingerprint.toLowerCase()}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(mapping.merchantFingerprint),
                      onPressed: _isSaving
                          ? null
                          : () {
                              final merchant = _merchants
                                  .where(
                                    (item) =>
                                        _stateKey(item) ==
                                        _normalizedFingerprint(
                                          mapping.merchantFingerprint,
                                        ),
                                  )
                                  .firstOrNull;
                              if (merchant != null) _chooseGroup([merchant]);
                            },
                      onDeleted: _isSaving
                          ? null
                          : () => _unassignMerchant(mapping),
                      deleteIcon: const Icon(Icons.close, size: 15),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    String title,
    double monthly,
    double annual,
    Color color,
  ) => Container(
    key: ValueKey(
      'baseline-metric-${title.toLowerCase().replaceAll(' ', '-')}',
    ),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      border: Border.all(color: color.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          '${formatFullCurrency(monthly, widget.currencySymbol)} / mo',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          '${formatFullCurrency(annual, widget.currencySymbol)} / yr normalized',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );

  Widget _buildUnderstandingSection(
    FinancialBaselineSummary summary,
    ColorScheme colors,
  ) {
    final identified = summary.identifiedBaselineMonthlyAverage;
    final adjustable = summary.potentiallyAdjustableMonthlyAverage;
    final classified = summary.classifiedPercentage / 100;
    return Container(
      key: const ValueKey('baseline-dashboard'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Understanding Your Spending',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'IDENTIFIED BASELINE',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.primary, fontWeight: FontWeight.w800),
          ),
          Text(
            '${formatFullCurrency(identified, widget.currencySymbol)} / mo',
            key: const ValueKey('identified-baseline'),
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: colors.primary),
          ),
          Text(
            'Essential ${formatFullCurrency(summary.essential.monthlyAverage, widget.currencySymbol)} + Committed ${formatFullCurrency(summary.committed.monthlyAverage, widget.currencySymbol)} per month. Based on historical spending and your classifications; this is not a definitive minimum cost of living.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Text(
            'POTENTIAL SPENDING ADJUSTMENTS',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${formatFullCurrency(adjustable, widget.currencySymbol)} / mo potentially adjustable',
            key: const ValueKey('potentially-adjustable'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Discretionary ${formatFullCurrency(summary.discretionary.monthlyAverage, widget.currencySymbol)} · Potentially Flexible ${formatFullCurrency(summary.potentiallyFlexible.monthlyAverage, widget.currencySymbol)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'This is spending you may review or optimize, not guaranteed savings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'SPENDING STILL TO UNDERSTAND',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${summary.unclassifiedPercentage.toStringAsFixed(0)}% unclassified',
                key: const ValueKey('unclassified-percentage'),
              ),
            ],
          ),
          Text(
            '${formatFullCurrency(summary.unclassifiedMonthlyAverage, widget.currencySymbol)} / mo unclassified · ${formatFullCurrency(summary.trackedMonthlyAverage, widget.currencySymbol)} / mo total ledger spending',
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: classified,
              minHeight: 9,
              backgroundColor: colors.errorContainer,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${summary.classifiedPercentage.toStringAsFixed(0)}% of spending classified by amount',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Map<String, (int, double)> _spendingByMerchant(BaselineGroup group) {
    final totals = <String, (int, double)>{};
    for (final match in _service.classify(
      transactions: _provider.transactions,
      mappings: _provider.mappings,
    )) {
      if (match.assignedGroup != group) continue;
      final name = _normalizer.normalize(match.transaction.description);
      if (name.isEmpty) continue;
      final current = totals[name] ?? (0, 0.0);
      totals[name] = (current.$1 + 1, current.$2 + match.transaction.amount);
    }
    return totals;
  }

  Widget _buildOpportunitySection(
    FinancialBaselineSummary summary,
    ColorScheme colors,
  ) {
    Widget groupBreakdown(BaselineGroup group) {
      final entries = _spendingByMerchant(group).entries.toList()
        ..sort((first, second) => second.value.$2.compareTo(first.value.$2));
      final top = entries.take(5).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.label} · ${formatFullCurrency(summary.metrics[group]!.monthlyAverage, widget.currencySymbol)} / mo',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: _groupColor(group),
              ),
            ),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No spending is assigned to this group yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final entry in top)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${entry.value.$1} transactions · ${formatFullCurrency(entry.value.$2 / (summary.monthCount == 0 ? 1 : summary.monthCount), widget.currencySymbol)} / mo average',
                  ),
                  trailing: Text(
                    formatFullCurrency(entry.value.$2, widget.currencySymbol),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('where-to-make-changes'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where You Can Make Changes',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Largest contributors by historical spending during the analysis period. Amounts are not savings estimates.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          groupBreakdown(BaselineGroup.discretionary),
          groupBreakdown(BaselineGroup.potentiallyFlexible),
        ],
      ),
    );
  }

  Widget _buildInsights(FinancialBaselineSummary summary, ColorScheme colors) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final recentStart = DateTime(now.year, now.month - 3);
    final previousStart = DateTime(now.year, now.month - 6);
    final classified = _service
        .classify(
          transactions: _provider.transactions,
          mappings: _provider.mappings,
        )
        .where((match) => match.assignedGroup == BaselineGroup.essential)
        .toList(growable: false);
    final recent = classified
        .where(
          (match) =>
              !match.transaction.date.isBefore(recentStart) &&
              match.transaction.date.isBefore(currentMonth),
        )
        .toList();
    final previous = classified
        .where(
          (match) =>
              !match.transaction.date.isBefore(previousStart) &&
              match.transaction.date.isBefore(recentStart),
        )
        .toList();
    final enoughHistory = recent.length >= 3 && previous.length >= 3;
    final recentAverage =
        recent.fold<double>(0, (sum, match) => sum + match.transaction.amount) /
        3;
    final previousAverage =
        previous.fold<double>(
          0,
          (sum, match) => sum + match.transaction.amount,
        ) /
        3;
    final trendMessage = enoughHistory && previousAverage > 0
        ? 'Recorded Essential spending averaged ${formatFullCurrency(recentAverage, widget.currencySymbol)} per month over the latest three completed months, ${((recentAverage - previousAverage).abs() / previousAverage * 100).round()}% ${recentAverage >= previousAverage ? 'higher' : 'lower'} than the previous three-month period.'
        : 'A historical comparison will appear after at least three Essential transactions are classified in each of the last two completed three-month periods.';
    return Container(
      key: const ValueKey('spending-insights'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Spending Insights',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insights_outlined),
            title: Text(trendMessage),
          ),
        ],
      ),
    );
  }

  Color _groupColor(BaselineGroup group) => switch (group) {
    BaselineGroup.essential => const Color(0xFF1B4D3E),
    BaselineGroup.committed => const Color(0xFF4267A5),
    BaselineGroup.discretionary => const Color(0xFF9A5A24),
    BaselineGroup.potentiallyFlexible => const Color(0xFF477080),
  };

  IconData _groupIcon(BaselineGroup group) => switch (group) {
    BaselineGroup.essential => Icons.home_outlined,
    BaselineGroup.committed => Icons.event_available_outlined,
    BaselineGroup.discretionary => Icons.spa_outlined,
    BaselineGroup.potentiallyFlexible => Icons.tune_outlined,
  };

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _provider.summary;
    final matches = _service.classify(
      transactions: _provider.transactions,
      mappings: _provider.mappings,
    );
    final conflicts = matches.where((match) => match.needsReview).toList();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Financial Baseline'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_draftRestored)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Restored unfinished changes'),
                ),
              if (_changedCount > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Preview – Unsaved Changes ($_changedCount)'),
                ),
              Row(
                children: [
                  if (_changedCount > 0 || _draftRestored)
                    TextButton(
                      onPressed: _isSaving ? null : _discardDraft,
                      child: const Text('Discard Changes'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const ValueKey('save-baseline-changes'),
                    onPressed: _isSaving || _changedCount == 0
                        ? null
                        : _commitDraft,
                    icon: const Icon(Icons.save_outlined),
                    label: Text('Save Changes ($_changedCount)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        key: const ValueKey('financial-baseline-screen-scroll'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          if (_changedCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                'Preview – Unsaved Changes',
                key: const ValueKey('baseline-unsaved-preview'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.tertiary,
                ),
              ),
            ),
          _buildUnderstandingSection(summary, colors),
          const SizedBox(height: 10),
          _buildOpportunitySection(summary, colors),
          const SizedBox(height: 10),
          _buildInsights(summary, colors),
          const SizedBox(height: 10),
          _buildOrganizer(colors),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${conflicts.length} transaction(s) match merchants assigned to multiple groups. '
                '${formatFullCurrency(summary.conflictAmount, widget.currencySymbol)} remains unclassified until mappings are resolved.',
                key: const ValueKey('baseline-mapping-conflicts'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (summary.ignoredCount > 0) ...[
            const SizedBox(height: 7),
            Text(
              '${summary.ignoredCount} transfer, card payment, refund, reversal, or invalid transaction(s) excluded.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 10),
          ExpansionTile(
            key: const ValueKey('baseline-detailed-breakdown'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            title: const Text('Detailed Breakdown'),
            subtitle: Text(
              'Lifestyle group totals · ${summary.monthCount} ${summary.monthCount == 1 ? 'month' : 'months'} analyzed',
            ),
            children: [
              for (final entry in [
                (
                  'Essential',
                  summary.essential,
                  _groupColor(BaselineGroup.essential),
                ),
                (
                  'Committed',
                  summary.committed,
                  _groupColor(BaselineGroup.committed),
                ),
                (
                  'Discretionary',
                  summary.discretionary,
                  _groupColor(BaselineGroup.discretionary),
                ),
                (
                  'Potentially Flexible',
                  summary.potentiallyFlexible,
                  _groupColor(BaselineGroup.potentiallyFlexible),
                ),
              ])
                _buildMetric(
                  entry.$1,
                  entry.$2.monthlyAverage,
                  entry.$2.annualizedAmount,
                  entry.$3,
                ),
              _buildMetric(
                'Unclassified',
                summary.unclassifiedMonthlyAverage,
                summary.unclassifiedAnnualizedAmount,
                colors.outline,
              ),
              _buildMetric(
                'Total Ledger Spending',
                summary.trackedMonthlyAverage,
                summary.trackedAnnualizedAmount,
                colors.primary,
              ),
              Text(
                'Lifestyle assignments are independent of Regular / Planned Occasional / Unexpected Occasional transaction frequency.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MerchantSort {
  highestSpending('Highest total spending'),
  mostTransactions('Most transactions'),
  merchantName('Merchant name');

  const _MerchantSort(this.label);
  final String label;
}
