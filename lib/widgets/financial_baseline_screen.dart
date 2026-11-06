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
  bool _saveReminderShownForBatch = false;
  bool _organizedExpanded = false;
  String? _saveStatus;
  final List<String> _draftConflictMerchants = [];
  final Map<BaselineGroup, TextEditingController> _groupSearchControllers = {};
  final Map<BaselineGroup, FocusNode> _groupSearchFocusNodes = {};
  final TextEditingController _unassignedSearchController =
      TextEditingController();
  final TextEditingController _organizedSearchController =
      TextEditingController();

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
    _unassignedSearchController.dispose();
    _organizedSearchController.dispose();
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

  void _selectMerchantFromSearch(
    BaselineGroup group,
    DiscoveredMerchant merchant,
  ) {
    _groupSearchControllers[group]?.clear();
    _groupSearchFocusNodes[group]?.requestFocus();
    _assignMerchants([merchant], group);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _groupSearchFocusNodes[group]?.requestFocus();
    });
  }

  Future<void> _unassignMerchant(FinancialBaselineMapping mapping) async {
    final updated = _mappings.where((candidate) => candidate.id != mapping.id);
    await _saveMappings(updated, showSuccessMessage: false);
  }

  Future<bool> _saveMappings(
    Iterable<FinancialBaselineMapping> mappings, {
    bool showSuccessMessage = true,
  }) async {
    final previousChangedCount = _changedCount;
    _provider.updateMappings(mappings);
    setState(() {
      _mappings = _provider.mappings;
      _saveStatus = null;
    });
    if (!_saveReminderShownForBatch &&
        previousChangedCount < 20 &&
        _changedCount >= 20) {
      _saveReminderShownForBatch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const ValueKey('baseline-save-reminder'),
              content: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "You've organized 20 merchants. Your changes are kept in a local draft.",
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('baseline-reminder-continue'),
                    onPressed: () =>
                        ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                    child: const Text('Continue'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'Save Now',
                onPressed: _commitDraft,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      });
    }
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
      if (mounted) {
        setState(() {
          _saveReminderShownForBatch = false;
          _draftRestored = false;
          _saveStatus = message ?? 'Saved locally.';
        });
      }
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
      _saveReminderShownForBatch = false;
      _mappings = _provider.mappings;
      _draftRestored = false;
      _saveStatus = null;
    });
  }

  Widget _buildOrganizer(ColorScheme colors) {
    return Container(
      key: const ValueKey('organize-your-spending'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organize Your Spending',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
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
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final groups = Column(
                children: [
                  for (final group in BaselineGroup.values) ...[
                    _buildGroupCard(group, colors),
                    if (group != BaselineGroup.values.last)
                      const SizedBox(height: 7),
                  ],
                ],
              );
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  groups,
                  const SizedBox(height: 8),
                  _buildOrganizedPanel(colors),
                ],
              );
              if (constraints.maxWidth < 850) {
                return Column(
                  key: const ValueKey('baseline-narrow-layout'),
                  children: [
                    left,
                    const SizedBox(height: 10),
                    _buildUnassignedPanel(colors, compact: false),
                  ],
                );
              }
              return Row(
                key: const ValueKey('baseline-wide-layout'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: _buildUnassignedPanel(colors, compact: true),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUnassignedPanel(ColorScheme colors, {required bool compact}) {
    final query = _normalizedFingerprint(_unassignedSearchController.text);
    final matches = _unassignedMerchants
        .where((merchant) {
          if (query.isEmpty) return true;
          return _normalizedFingerprint(merchant.merchantFingerprint)
                  .contains(query) ||
              (_merchantSearchIndex[_stateKey(merchant)]?.contains(query) ??
                  false);
        })
        .take(20)
        .toList(growable: false);
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              '${_unassignedMerchants.length} left · ${matches.length} shown',
              key: const ValueKey('unassigned-visible-count'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('unassigned-merchant-search'),
          controller: _unassignedSearchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search all unassigned merchants',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('clear-unassigned-search'),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _unassignedSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        Row(
          children: [
            const Text('Sort by'),
            const SizedBox(width: 6),
            DropdownButton<_MerchantSort>(
              key: const ValueKey('merchant-sort-order'),
              value: _merchantSort,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: _MerchantSort.highestSpending,
                  child: Text('Total spending'),
                ),
                DropdownMenuItem(
                  value: _MerchantSort.mostTransactions,
                  child: Text('Transactions'),
                ),
                DropdownMenuItem(
                  value: _MerchantSort.merchantName,
                  child: Text('Name'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _merchantSort = value);
              },
            ),
          ],
        ),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'All merchants are assigned.'
                        : 'No merchants match your search.',
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('unassigned-merchant-list'),
                  itemCount: matches.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colors.outlineVariant),
                  itemBuilder: (context, index) {
                    final merchant = matches[index];
                    return Padding(
                      key: ValueKey('unassigned-${_stateKey(merchant)}'),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  merchant.merchantFingerprint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${formatFullCurrency(merchant.totalAmount, widget.currencySymbol)} · ${merchant.occurrenceCount} transactions',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: ValueKey(
                              'assign-merchant-${_stateKey(merchant)}',
                            ),
                            onPressed: _isSaving
                                ? null
                                : () => _chooseGroup([merchant]),
                            child: const Text('Assign'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('unassigned-merchants-panel'),
      height: compact
          ? (MediaQuery.sizeOf(context).height * .72).clamp(430, 720).toDouble()
          : 480,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: list,
    );
  }

  Widget _buildOrganizedPanel(ColorScheme colors) {
    final query = _normalizedFingerprint(_organizedSearchController.text);
    final assigned =
        _mappings.where((mapping) {
          if (query.isEmpty) return true;
          return _normalizedFingerprint(mapping.merchantFingerprint)
                  .contains(query) ||
              (_merchantSearchIndex[_normalizedFingerprint(
                        mapping.merchantFingerprint,
                      )]
                      ?.contains(query) ??
                  false);
        }).toList()..sort((a, b) {
          final groupOrder = a.group.index.compareTo(b.group.index);
          return groupOrder != 0
              ? groupOrder
              : a.merchantFingerprint.toLowerCase().compareTo(
                  b.merchantFingerprint.toLowerCase(),
                );
        });
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('organized-merchants-expansion'),
        initiallyExpanded: _organizedExpanded,
        onExpansionChanged: (expanded) =>
            setState(() => _organizedExpanded = expanded),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        title: Text(
          'Organized Merchants (${_mappings.length})',
          key: const ValueKey('organized-merchants-title'),
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          'Review or change merchants you\'ve already assigned.',
        ),
        children: [
          TextField(
            key: const ValueKey('organized-merchant-search'),
            controller: _organizedSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search assigned merchants',
              border: const OutlineInputBorder(),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('clear-organized-search'),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _organizedSearchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          if (assigned.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                query.isEmpty
                    ? 'No assigned merchants yet.'
                    : 'No assigned merchants match your search.',
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                key: const ValueKey('organized-merchant-list'),
                shrinkWrap: true,
                children: [
                  for (final group in BaselineGroup.values) ...[
                    if (assigned.any((mapping) => mapping.group == group))
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Row(
                          children: [
                            Icon(
                              _groupIcon(group),
                              size: 17,
                              color: _groupColor(group),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              group.label,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: _groupColor(group),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    for (final mapping in assigned.where(
                      (mapping) => mapping.group == group,
                    ))
                      Row(
                        key: ValueKey(
                          'organized-${group.name}-${_normalizedFingerprint(mapping.merchantFingerprint)}',
                        ),
                        children: [
                          Expanded(
                            child: Text(
                              mapping.merchantFingerprint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey(
                              'organized-actions-${_normalizedFingerprint(mapping.merchantFingerprint)}',
                            ),
                            tooltip: 'Change assignment or remove',
                            enabled: !_isSaving,
                            onSelected: (action) {
                              if (action == 'remove') {
                                _unassignMerchant(mapping);
                              } else if (action.startsWith('move:')) {
                                final destination = BaselineGroup.values
                                    .firstWhere(
                                      (candidate) =>
                                          candidate.name == action.substring(5),
                                    );
                                if (destination != mapping.group) {
                                  _replaceMappingGroup(mapping, destination);
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              for (final destination in BaselineGroup.values)
                                PopupMenuItem<String>(
                                  value: 'move:${destination.name}',
                                  enabled: destination != mapping.group,
                                  child: Text('Move to ${destination.label}'),
                                ),
                              const PopupMenuDivider(),
                              const PopupMenuItem<String>(
                                value: 'remove',
                                child: Text('Remove assignment'),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _replaceMappingGroup(
    FinancialBaselineMapping mapping,
    BaselineGroup group,
  ) async {
    final updated = _mappings.where((item) => item.id != mapping.id).toList()
      ..add(
        FinancialBaselineMapping(
          merchantFingerprint: mapping.merchantFingerprint,
          group: group,
        ),
      );
    await _saveMappings(updated, showSuccessMessage: false);
  }

  Widget _buildGroupCard(BaselineGroup group, ColorScheme colors) {
    final mappings = _mappings
        .where((mapping) => mapping.group == group)
        .toList(growable: false);
    final available = _unassignedMerchants;
    final tint = _groupColor(group);
    return Container(
      key: ValueKey('baseline-group-${group.name}'),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
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
                '${mappings.length} assigned',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 3),
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
            onSelected: (merchant) =>
                _selectMerchantFromSearch(group, merchant),
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
                (context, controller, focusNode, onFieldSubmitted) {
                  _groupSearchControllers[group] = controller;
                  _groupSearchFocusNodes[group] = focusNode;
                  return TextField(
                    key: ValueKey('group-search-${group.name}'),
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      hintText: 'Add merchant',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 6,
                      ),
                    ),
                  );
                },
          ),
        ],
      ),
    );
  }

  Widget _buildClassificationProgress(
    FinancialBaselineSummary summary,
    ColorScheme colors,
  ) {
    final percentage = summary.classifiedPercentage;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final progress = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    Text(
                      '${percentage.toStringAsFixed(0)}% classified by spending amount',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${formatFullCurrency(summary.unclassifiedMonthlyAverage, widget.currencySymbol)} / mo unclassified',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    key: const ValueKey('classification-progress'),
                    value: percentage / 100,
                    minHeight: 6,
                    color: colors.primary,
                    backgroundColor: colors.errorContainer,
                  ),
                ),
              ],
            );
            final action = OutlinedButton.icon(
              key: const ValueKey('view-baseline-insights'),
              onPressed: _openInsights,
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('View Insights'),
            );
            if (constraints.maxWidth < 550) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  progress,
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: progress),
                const SizedBox(width: 10),
                action,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openInsights() async {
    final summary = _provider.summary;
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 600) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .86,
            ),
            child: _insightsDialogBody(summary, colors),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .92,
          child: _insightsDialogBody(summary, colors),
        ),
      );
    }
  }

  Widget _insightsDialogBody(
    FinancialBaselineSummary summary,
    ColorScheme colors,
  ) {
    final readiness = baselineInsightReadiness(summary.classifiedPercentage);
    final contributors = [..._merchants]
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    final trend = readiness == BaselineInsightReadiness.insufficient
        ? null
        : _supportedTrend();
    final isUnsaved = _changedCount > 0;
    Widget amountCard(String title, String value, Color color) => Container(
      constraints: const BoxConstraints(minWidth: 205),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border.all(color: color.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Text('per month, normalized'),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Spending Insights',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (isUnsaved)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(label: Text('Unsaved')),
                ),
              IconButton(
                tooltip: 'Close insights',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('baseline-insights-scroll'),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Completeness is measured by spending amount. These thresholds guide how much context to show; they do not guarantee accuracy.',
                ),
                const SizedBox(height: 12),
                Text(
                  '${summary.classifiedPercentage.toStringAsFixed(0)}% classified · ${formatFullCurrency(summary.unclassifiedMonthlyAverage, widget.currencySymbol)} / mo unclassified',
                  key: const ValueKey('insights-classification-status'),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: summary.classifiedPercentage / 100,
                    minHeight: 8,
                    color: colors.primary,
                    backgroundColor: colors.errorContainer,
                  ),
                ),
                if (readiness == BaselineInsightReadiness.insufficient) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('insights-insufficient-data'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'There is not enough classified spending yet for representative baseline insights. Organize more merchants to build a clearer picture.',
                    ),
                  ),
                ] else ...[
                  if (readiness == BaselineInsightReadiness.provisional)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        key: const ValueKey('insights-incomplete-warning'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.tertiaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Provisional insights: some spending is still unclassified.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      amountCard(
                        'Identified Baseline',
                        '${formatFullCurrency(summary.identifiedBaselineMonthlyAverage, widget.currencySymbol)} / mo',
                        _groupColor(BaselineGroup.essential),
                      ),
                      amountCard(
                        'Potentially Adjustable',
                        '${formatFullCurrency(summary.potentiallyAdjustableMonthlyAverage, widget.currencySymbol)} / mo',
                        _groupColor(BaselineGroup.potentiallyFlexible),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Top spending contributors',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  for (final merchant in contributors.take(5))
                    ListTile(
                      key: ValueKey(
                        'insight-contributor-${_stateKey(merchant)}',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        merchant.merchantFingerprint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${merchant.occurrenceCount} transactions',
                      ),
                      trailing: Text(
                        formatFullCurrency(
                          merchant.totalAmount,
                          widget.currencySymbol,
                        ),
                      ),
                    ),
                  if (trend != null) ...[
                    const Divider(),
                    Text(
                      'Historical trend',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      trend,
                      key: const ValueKey('baseline-supported-trend'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _supportedTrend() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final recentStart = DateTime(now.year, now.month - 3);
    final previousStart = DateTime(now.year, now.month - 6);
    final essential = _service
        .classify(transactions: _provider.transactions, mappings: _mappings)
        .where((match) => match.assignedGroup == BaselineGroup.essential);
    final recent = essential
        .where(
          (match) =>
              !match.transaction.date.isBefore(recentStart) &&
              match.transaction.date.isBefore(currentMonth),
        )
        .toList();
    final previous = essential
        .where(
          (match) =>
              !match.transaction.date.isBefore(previousStart) &&
              match.transaction.date.isBefore(recentStart),
        )
        .toList();
    if (recent.length < 3 || previous.length < 3) return null;
    final recentAverage =
        recent.fold<double>(0, (sum, match) => sum + match.transaction.amount) /
        3;
    final previousAverage =
        previous.fold<double>(
          0,
          (sum, match) => sum + match.transaction.amount,
        ) /
        3;
    if (previousAverage <= 0) return null;
    final change =
        ((recentAverage - previousAverage).abs() / previousAverage * 100)
            .round();
    return 'Essential spending averaged ${formatFullCurrency(recentAverage, widget.currencySymbol)} / mo in the latest three completed months, $change% ${recentAverage >= previousAverage ? 'higher' : 'lower'} than the prior three months.';
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
              if (_changedCount == 0 && _saveStatus != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _saveStatus!,
                    key: const ValueKey('baseline-save-status'),
                  ),
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
          _buildClassificationProgress(summary, colors),
          const SizedBox(height: 8),
          _buildOrganizer(colors),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${conflicts.length} transaction(s) have overlapping merchant groups and remain unclassified.',
              key: const ValueKey('baseline-mapping-conflicts'),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.error),
            ),
          ],
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
