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
  });

  final List<Transaction> transactions;
  final List<FinancialBaselineMapping> initialMappings;
  final String currencySymbol;
  final Future<String?> Function(List<FinancialBaselineMapping>)
  onMappingsSaved;

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
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedMerchants = {};
  bool _isMultiSelectMode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _provider = FinancialBaselineProvider(
      transactions: widget.transactions,
      mappings: widget.initialMappings,
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
    _searchController.dispose();
    _provider.dispose();
    super.dispose();
  }

  String _normalizedFingerprint(String value) =>
      _normalizer.normalize(value).trim().toLowerCase();

  bool _hasMapping(String fingerprint) {
    final normalized = _normalizedFingerprint(fingerprint);
    return _mappings.any(
      (mapping) =>
          _normalizedFingerprint(mapping.merchantFingerprint) == normalized,
    );
  }

  List<DiscoveredMerchant> _unmappedMerchants() => _merchants
      .where((merchant) => !_hasMapping(merchant.merchantFingerprint))
      .toList(growable: false);

  void _selectMerchant(DiscoveredMerchant merchant) {
    if (_isMultiSelectMode) {
      _toggleSelection(merchant);
    } else {
      _chooseGroup([merchant]);
    }
  }

  void _toggleSelection(DiscoveredMerchant merchant) {
    final fingerprint = _normalizedFingerprint(merchant.merchantFingerprint);
    setState(() {
      _isMultiSelectMode = true;
      if (!_selectedMerchants.add(fingerprint)) {
        _selectedMerchants.remove(fingerprint);
      }
    });
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
    if (mounted) {
      setState(() {
        _selectedMerchants.clear();
        _isMultiSelectMode = false;
      });
    }
  }

  Future<void> _unassignMerchant(FinancialBaselineMapping mapping) async {
    final updated = _mappings.where((candidate) => candidate.id != mapping.id);
    await _saveMappings(updated, showSuccessMessage: false);
  }

  Future<void> _saveMappings(
    Iterable<FinancialBaselineMapping> mappings, {
    bool showSuccessMessage = true,
  }) async {
    final previousMappings = _mappings;
    _provider.updateMappings(mappings);
    setState(() {
      _mappings = _provider.mappings;
      _isSaving = true;
    });
    try {
      final message = await widget.onMappingsSaved(
        List.unmodifiable(_mappings),
      );
      if (mounted && (message != null || showSuccessMessage)) {
        _showMessage(message ?? 'Financial baseline saved.');
      }
    } catch (error) {
      _provider.updateMappings(previousMappings);
      if (mounted) {
        setState(() => _mappings = _provider.mappings);
        _showMessage('Could not save financial baseline: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildMerchantPool(ColorScheme colors) {
    final searchTerm = _searchController.text.trim().toLowerCase();
    final allUnmapped = _unmappedMerchants();
    final filtered = allUnmapped
        .where((merchant) {
          if (searchTerm.isEmpty) return true;
          final fingerprint = _normalizedFingerprint(
            merchant.merchantFingerprint,
          );
          return fingerprint.contains(searchTerm) ||
              (_merchantSearchIndex[fingerprint]?.contains(searchTerm) ??
                  false);
        })
        .toList(growable: false);
    return Container(
      key: const ValueKey('all-merchants-pool'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Unassigned Merchants',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${filtered.length} remaining',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                key: const ValueKey('toggle-merchant-multi-select'),
                onPressed: () => setState(() {
                  _isMultiSelectMode = !_isMultiSelectMode;
                  _selectedMerchants.clear();
                }),
                icon: Icon(
                  _isMultiSelectMode ? Icons.close : Icons.checklist,
                  size: 18,
                ),
                label: Text(_isMultiSelectMode ? 'Cancel' : 'Select'),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('all-merchants-search'),
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search merchants',
              suffixIcon: searchTerm.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('clear-merchant-search'),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            searchTerm.isEmpty
                ? '${allUnmapped.length} unassigned merchants'
                : '${filtered.length} of ${allUnmapped.length} merchants',
            key: const ValueKey('merchant-search-result-count'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          if (allUnmapped.isEmpty)
            const Text('Every discovered merchant is assigned.')
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No merchants match your search. Try another term or clear it.',
                key: ValueKey('merchant-search-empty-state'),
              ),
            )
          else
            SizedBox(
              height: 164,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  children: [
                    for (final merchant in filtered)
                      _MerchantChip(
                        key: ValueKey(
                          'unmapped-merchant-${merchant.merchantFingerprint.toLowerCase()}',
                        ),
                        merchant: merchant,
                        currencySymbol: widget.currencySymbol,
                        selected: _selectedMerchants.contains(
                          _normalizedFingerprint(merchant.merchantFingerprint),
                        ),
                        onTap: () => _selectMerchant(merchant),
                        onLongPress: () => _toggleSelection(merchant),
                      ),
                  ],
                ),
              ),
            ),
          if (_isMultiSelectMode)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Tap or long-press merchants to select them.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
    final tint = _groupColor(group);
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
          Padding(
            padding: const EdgeInsets.only(left: 31, top: 2),
            child: Text(
              '${formatFullCurrency(metrics.annualizedAmount, widget.currencySymbol)} / yr normalized',
              style: Theme.of(context).textTheme.labelSmall,
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

  Color _groupColor(BaselineGroup group) => switch (group) {
    BaselineGroup.essential => const Color(0xFF1B4D3E),
    BaselineGroup.committed => const Color(0xFF4267A5),
    BaselineGroup.discretionary => const Color(0xFF9A5A24),
  };

  IconData _groupIcon(BaselineGroup group) => switch (group) {
    BaselineGroup.essential => Icons.home_outlined,
    BaselineGroup.committed => Icons.event_available_outlined,
    BaselineGroup.discretionary => Icons.spa_outlined,
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
    final selected = _merchants
        .where(
          (merchant) => _selectedMerchants.contains(
            _normalizedFingerprint(merchant.merchantFingerprint),
          ),
        )
        .toList(growable: false);

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
      bottomNavigationBar: selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: FilledButton.icon(
                  key: const ValueKey('assign-selected-merchants'),
                  onPressed: _isSaving ? null : () => _chooseGroup(selected),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text('Assign ${selected.length} selected merchants'),
                ),
              ),
            ),
      body: ListView(
        key: const ValueKey('financial-baseline-screen-scroll'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          Container(
            key: const ValueKey('baseline-dashboard'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: colors.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'YOUR BASELINE',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${summary.monthCount} ${summary.monthCount == 1 ? 'month' : 'months'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Assign each merchant directly to a lifestyle group. '
                  'Group choices are yours and do not change transaction frequency types.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 520 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 7) / columns;
                    final entries = [
                      (
                        'Essential',
                        summary.essential.monthlyAverage,
                        summary.essential.annualizedAmount,
                        _groupColor(BaselineGroup.essential),
                      ),
                      (
                        'Committed',
                        summary.committed.monthlyAverage,
                        summary.committed.annualizedAmount,
                        _groupColor(BaselineGroup.committed),
                      ),
                      (
                        'Discretionary',
                        summary.discretionary.monthlyAverage,
                        summary.discretionary.annualizedAmount,
                        _groupColor(BaselineGroup.discretionary),
                      ),
                      (
                        'Potentially Flexible',
                        summary.potentiallyFlexible.monthlyAverage,
                        summary.potentiallyFlexible.annualizedAmount,
                        colors.tertiary,
                      ),
                      (
                        'Unclassified',
                        summary.unclassifiedMonthlyAverage,
                        summary.unclassifiedAnnualizedAmount,
                        colors.outline,
                      ),
                      (
                        'Total Ledger Spending',
                        summary.trackedMonthlyAverage,
                        summary.trackedAnnualizedAmount,
                        colors.primary,
                      ),
                    ];
                    return Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final entry in entries)
                          SizedBox(
                            width: width,
                            child: _buildMetric(
                              entry.$1,
                              entry.$2,
                              entry.$3,
                              entry.$4,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildMerchantPool(colors),
          const SizedBox(height: 10),
          Text(
            'Lifestyle groups',
            key: const ValueKey('baseline-groups-heading'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final group in BaselineGroup.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildGroupCard(
                            group,
                            summary.metrics[group]!,
                            colors,
                          ),
                        ),
                      ),
                  ],
                );
              }
              return Column(
                children: [
                  for (final group in BaselineGroup.values) ...[
                    _buildGroupCard(group, summary.metrics[group]!, colors),
                    const SizedBox(height: 7),
                  ],
                ],
              );
            },
          ),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${conflicts.length} transaction(s) matched merchants assigned to multiple groups. '
                '${formatFullCurrency(summary.conflictAmount, widget.currencySymbol)} is excluded from group totals until reviewed.',
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
        ],
      ),
    );
  }
}

class _MerchantChip extends StatelessWidget {
  const _MerchantChip({
    super.key,
    required this.merchant,
    required this.currencySymbol,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final DiscoveredMerchant merchant;
  final String currencySymbol;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onLongPress,
    child: ActionChip(
      onPressed: onTap,
      avatar: Icon(
        selected ? Icons.check_circle : Icons.storefront_outlined,
        size: 17,
      ),
      side: selected
          ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
          : null,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(merchant.merchantFingerprint),
          Text(
            '${merchant.occurrenceCount} · ${formatFullCurrency(merchant.averageAmount, currencySymbol)} avg',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}
