import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/expense_category.dart';
import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import '../services/favourite_spending_spots_service.dart';
import '../services/financial_baseline_service.dart';
import '../services/merchant_classification_service.dart';
import '../services/merchant_classification_store.dart';
import '../services/merchant_na_service.dart';
import '../utils/currency_format.dart';
import 'pocket_ledger_web_access.dart';

List<FavouriteSpendingSpot> merchantsForCoverage(
  List<FavouriteSpendingSpot> groups,
  double target,
) {
  final total = groups.fold<double>(0, (s, g) => s + g.total);
  if (total <= 0) return [];
  final selected = <FavouriteSpendingSpot>[];
  var covered = 0.0;
  for (final group in groups) {
    selected.add(group);
    covered += group.total;
    if (covered / total >= target) break;
  }
  return selected;
}

class MerchantBaselinePanel extends StatefulWidget {
  const MerchantBaselinePanel({
    super.key,
    required this.transactions,
    required this.categories,
    required this.legacyMappings,
    required this.store,
    required this.currencySymbol,
    required this.onSaved,
    this.historyComplete = false,
    this.showRemainingInitially = false,
    this.reviewUnknownInitially = false,
    this.showClassifiedInitially = false,
  });
  final List<Transaction> transactions;
  final List<ExpenseCategory> categories;
  final List<FinancialBaselineMapping> legacyMappings;
  final MerchantClassificationStore store;
  final String currencySymbol;
  final bool historyComplete;
  final bool showRemainingInitially;
  final bool reviewUnknownInitially;
  final bool showClassifiedInitially;
  final Future<String> Function(List<Map<String, dynamic>>) onSaved;
  @override
  State<MerchantBaselinePanel> createState() => _MerchantBaselinePanelState();
}

class _MerchantBaselinePanelState extends State<MerchantBaselinePanel> {
  late Map<String, Map<String, dynamic>> _draft;
  final _changed = <String>{};
  final _expanded = <String>{};
  // Keep work-list membership and progress stable until edits are saved.
  final _classifiedKeys = <String>{};
  final _unknownAmounts = <String, double>{};
  final _naKeys = <String>{};
  final _naThreshold = TextEditingController();
  bool _showNaControls = false;
  bool _merchantsExpanded = false;

  String? _naError;
  bool _filtersOpen = false;
  String? _filterCategory;
  String? _filterGroup;
  String? _filterType;
  final _savedReviewTransactions = <String, List<Transaction>>{};
  late List<FavouriteSpendingSpot> _groups;
  late Map<Transaction, String?> _legacy;
  String _selection = '80%';
  String _view = 'overview';
  bool _reviewCoverage = false;
  String _query = '';
  bool _saving = false;
  String? _status;
  MerchantClassificationIndex? _indexCache;
  MerchantClassificationIndex get _index =>
      _indexCache ??= MerchantClassificationIndex(_draft.values);
  String money(double n) => formatFullCurrency(n, widget.currencySymbol);

  String? get _activeSection {
    if (!_merchantsExpanded) return null;
    return switch (_view) {
      'classified' => 'classified',
      'na' => 'na',
      'remaining' || 'focus' || 'unknown' => 'remaining',
      _ => null,
    };
  }

  int get _changedMerchantCount {
    final changedTransactions = <String>{
      for (final id in _changed)
        if (_draft[id]?['kind'] == 'transaction')
          _draft[id]!['transactionId'].toString(),
    };
    final changedAliases = <String>{
      for (final id in _changed)
        if (_draft[id]?['kind'] == 'merchant')
          for (final alias in (_draft[id]?['aliases'] as List? ?? []))
            merchantClassificationKey(alias.toString()),
    };
    return _groups.where((group) {
      return _changed.contains('m:${group.key}') ||
          group.transactions.any(
            (entry) =>
                changedTransactions.contains(entry.transaction.id) ||
                changedAliases.contains(
                  merchantClassificationKey(entry.transaction.description),
                ),
          );
    }).length;
  }

  Future<void> _openSection(String section) async {
    if (_saving) return;
    final collapse = _activeSection == section;
    if (_activeSection != null && _changed.isNotEmpty) {
      final count = _changedMerchantCount;
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text(
            '$count ${count == 1 ? 'merchant has' : 'merchants have'} changes. Save or ignore them before continuing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'ignore'),
              child: const Text('Ignore'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'save') {
        await _save();
      } else {
        await _discardDraft();
      }
      if (!mounted) return;
      if (_changed.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(_status ?? 'Could not save changes.')),
        );
        return;
      }
    }
    setState(() {
      _merchantsExpanded = !collapse;
      if (!collapse) {
        _view = section;
        _selection = 'All';
        _query = '';
        _reviewCoverage = false;
        _expanded.clear();
        _showNaControls = false;
      }
    });
  }

  void _showCoverageDetails(
    List<(String, String, Color, int, double)> sections,
    double total,
    String? history,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final heading = theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        );
        return AlertDialog(
          title: const Text('Financial Baseline details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Spending coverage', style: heading),
                const SizedBox(height: 8),
                Column(
                  key: const ValueKey('baseline-coverage-summary'),
                  children: [
                    for (final section in sections)
                      Padding(
                        key: ValueKey('baseline-coverage-${section.$1}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5, right: 8),
                              child: Icon(
                                Icons.circle,
                                size: 10,
                                color: section.$3,
                              ),
                            ),
                            Expanded(child: Text(section.$2)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${(total <= 0 ? 0.0 : section.$5 / total * 100).toStringAsFixed(1)}% · ${money(section.$5)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Coverage is based on eligible spending, not merchant count.',
                  style: theme.textTheme.bodySmall,
                ),
                if (history != null) ...[
                  const SizedBox(height: 16),
                  Text('Available history', style: heading),
                  const SizedBox(height: 4),
                  Text(history, key: const ValueKey('baseline-history-period')),
                ],
                const SizedBox(height: 16),
                Text('Merchant choices', style: heading),
                const SizedBox(height: 4),
                const Text(
                  'Choices apply to all transactions for a merchant. Expand a merchant to edit individual transactions.',
                ),
                const SizedBox(height: 16),
                Text('How choices are used', style: heading),
                const SizedBox(height: 4),
                const Text('Category → category breakdowns'),
                const Text('Expense Type → budgets'),
                const Text('Essentiality → insights'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.showRemainingInitially) _view = 'remaining';
    if (widget.reviewUnknownInitially) _view = 'unknown';
    if (widget.showClassifiedInitially) _view = 'classified';
    _merchantsExpanded =
        widget.showRemainingInitially ||
        widget.reviewUnknownInitially ||
        widget.showClassifiedInitially;
    _draft = {
      for (final r in widget.store.records.values)
        r['id'] as String: Map<String, dynamic>.from(r),
    };
    final savedLimit = widget.store.records[merchantNaPolicyId]?['threshold'];
    if (savedLimit is num) _naThreshold.text = savedLimit.toString();
    _draft.addAll(widget.store.draft);
    _changed.addAll(widget.store.draft.keys);
    _prepare();
    _refreshClassification(widget.store.index);
  }

  bool _complete(
    FavouriteSpendingSpot group,
    MerchantClassificationIndex index,
  ) => group.transactions.every((entry) {
    final t = index.apply(entry.transaction);
    final categoryKnown = widget.categories.any(
      (c) => c.id == t.categoryId || c.name == t.category,
    );
    final essentiality = t.baselineGroup ?? _legacy[entry.transaction];
    return categoryKnown &&
        essentiality != null &&
        essentiality != 'Unclassified' &&
        t.expenseType != ExpenseType.unknown;
  });

  void _refreshClassification(MerchantClassificationIndex index) {
    _savedReviewTransactions.clear();
    for (final group in _groups) {
      _savedReviewTransactions[group.key] = group.transactions.map((entry) {
        final effective = index.apply(entry.transaction);
        return effective.copyWith(
          baselineGroup: effective.baselineGroup ?? _legacy[entry.transaction],
        );
      }).toList();
    }
    _naKeys
      ..clear()
      ..addAll(
        _groups
            .where(
              (g) =>
                  index.merchantFor(
                    g.transactions.first.transaction.description,
                  )?['na'] ==
                  true,
            )
            .map((g) => g.key),
      );
    _classifiedKeys
      ..clear()
      ..addAll(
        _groups
            .where((g) => !_naKeys.contains(g.key) && _complete(g, index))
            .map((g) => g.key),
      );
    _unknownAmounts.clear();
    for (final group in _groups) {
      final unknown = group.transactions.where(
        (entry) =>
            index.apply(entry.transaction).expenseType == ExpenseType.unknown,
      );
      if (unknown.isNotEmpty)
        _unknownAmounts[group.key] = unknown.fold<double>(
          0,
          (sum, entry) => sum + entry.transaction.amount,
        );
    }
  }

  int get _filterCount =>
      [_filterCategory, _filterGroup, _filterType].whereType<String>().length;

  bool _matchesReviewFilters(FavouriteSpendingSpot group) =>
      _view != 'classified' ||
      (_savedReviewTransactions[group.key] ?? []).any(
        (t) =>
            (_filterCategory == null || t.category == _filterCategory) &&
            (_filterGroup == null || t.baselineGroup == _filterGroup) &&
            (_filterType == null || t.expenseType.sheetValue == _filterType),
      );

  Widget _reviewFilters() {
    final categories = {
      for (final c in widget.categories) c.name,
      for (final transactions in _savedReviewTransactions.values)
        for (final t in transactions) t.category,
    }.toList()..sort();
    Widget field(
      String key,
      String label,
      String? value,
      List<String> options,
      ValueChanged<String?> change,
    ) => SizedBox(
      width: 200,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: ValueKey(key),
            value: value ?? '__all',
            isExpanded: true,
            isDense: true,
            items: [
              DropdownMenuItem(
                value: '__all',
                child: Text('All ${label.toLowerCase()}'),
              ),
              for (final option in {...options, if (value != null) value})
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => change(v == '__all' ? null : v)),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (_, constraints) {
              final width = constraints.maxWidth < 640
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: field(
                      'baseline-filter-category',
                      'Categories',
                      _filterCategory,
                      categories,
                      (v) => _filterCategory = v,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: field(
                      'baseline-filter-group',
                      'Essentiality',
                      _filterGroup,
                      ['Essential', 'Potentially Flexible', 'Unclassified'],
                      (v) => _filterGroup = v,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: field(
                      'baseline-filter-type',
                      'Expense Types',
                      _filterType,
                      ExpenseType.values.map((t) => t.sheetValue).toList(),
                      (v) => _filterType = v,
                    ),
                  ),
                ],
              );
            },
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Includes matching transaction exceptions.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              TextButton(
                key: const ValueKey('baseline-clear-filters'),
                onPressed: () => setState(() {
                  _filterCategory = null;
                  _filterGroup = null;
                  _filterType = null;
                }),
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _naThreshold.dispose();
    super.dispose();
  }

  Future<void> _applyNa() async {
    final threshold = merchantNaThreshold(_naThreshold.text);
    if (threshold == null) {
      setState(() => _naError = 'Enter a valid amount of at least 0.01.');
      return;
    }
    if (_changed.isNotEmpty) {
      setState(() => _naError = 'Save or discard your pending edits first.');
      return;
    }
    final preview = _unclassifiedNaPreview(threshold);
    final index = _index;
    setState(() {
      _naError = null;
      _draft[merchantNaPolicyId] = merchantNaPolicyRecord(threshold);
      _changed.add(merchantNaPolicyId);
      for (final group in preview.groups) {
        final record = merchantNaRecord(group, index, threshold: threshold);
        _draft[record['id'] as String] = record;
        _changed.add(record['id'] as String);
      }
      _indexCache = null;
      _summaryCache.clear();
      _persistDraft();
    });
    await _save();
    if (mounted && _changed.isEmpty) {
      setState(() {
        _view = 'na';
        _query = '';
        _showNaControls = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '${preview.groups.length} additional merchants excluded · ${money(preview.amount)} newly excluded. ${_status ?? ''} Merchants stay excluded while their total expenses are below ${money(threshold)}.',
          ),
        ),
      );
    }
  }

  MerchantNaPreview _unclassifiedNaPreview(double threshold) {
    final preview = previewMerchantNa(_groups, threshold);
    return MerchantNaPreview(
      preview.groups.where((g) {
        if (_classifiedKeys.contains(g.key) || _naKeys.contains(g.key))
          return false;
        final rules = <String>{};
        for (final entry in g.transactions) {
          final description = entry.transaction.description;
          if (_index.isAmbiguous(description)) return false;
          final rule = _index.merchantFor(description);
          if (rule?['naOptOut'] == true || rule?['naReviewRequired'] == true)
            return false;
          if (rule != null) rules.add(rule['id'] as String);
        }
        return rules.length <= 1;
      }).toList(),
      preview.totalSpending,
      preview.totalTransactions,
    );
  }

  void _removeNa(FavouriteSpendingSpot group) {
    final record = _rule(group);
    if (record == null) return;
    final changes = removeMerchantNa(record, _index);
    setState(() {
      for (final change in changes) {
        _draft[change['id'] as String] = change;
        _changed.add(change['id'] as String);
      }
      _indexCache = null;
      _summaryCache.clear();
      _persistDraft();
    });
  }

  Widget _naControls() {
    final threshold = merchantNaThreshold(_naThreshold.text);
    final preview = threshold == null
        ? null
        : _unclassifiedNaPreview(threshold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: FilledButton.tonalIcon(
            key: const ValueKey('na-threshold-toggle'),
            onPressed: _saving
                ? null
                : () => setState(() => _showNaControls = !_showNaControls),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            icon: const Icon(Icons.playlist_add_check, size: 24),
            label: const Text(
              'Bulk Exclude Small Merchants',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (_showNaControls) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final amount = TextField(
                key: const ValueKey('na-threshold'),
                controller: _naThreshold,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: widget.currencySymbol,
                  hintText: 'Amount',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _naError = null),
              );
              final exclude = FilledButton(
                key: const ValueKey('save-na-threshold'),
                onPressed: _saving ? null : _applyNa,
                child: const Text('Exclude'),
              );
              if (constraints.maxWidth < 500) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Exclude all merchants <'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: amount),
                        const SizedBox(width: 12),
                        exclude,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  const Text('Exclude all merchants <'),
                  const SizedBox(width: 12),
                  SizedBox(width: 160, child: amount),
                  const SizedBox(width: 12),
                  exclude,
                ],
              );
            },
          ),
          if (_naError != null)
            Text(
              _naError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          if (preview != null) ...[
            const SizedBox(height: 10),
            Text(
              '${preview.groups.length} merchants · ${money(preview.amount)} · ${preview.spendingPercent.toStringAsFixed(1)}% of spending',
              key: const ValueKey('na-live-preview'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'New exclusions only. Existing transaction exceptions stay.',
              style: TextStyle(fontSize: 12),
            ),
            if (_naKeys.isNotEmpty)
              Text(
                'Already excluded: ${_naKeys.length} merchants.',
                style: const TextStyle(fontSize: 12),
              ),
          ],
          if (preview != null && preview.transactionPercent > 25)
            Text(
              'Excludes ${preview.transactionPercent.toStringAsFixed(1)}% of transactions (over 25%); this may affect insights.',
              key: const ValueKey('na-impact-warning'),
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ],
    );
  }

  void _prepare() {
    _groups = const FavouriteSpendingSpotsService()
        .calculate(transactions: widget.transactions, allHistory: true)
        .actual;
    _legacy = {
      for (final m in FinancialBaselineService().classify(
        transactions: widget.transactions,
        mappings: widget.legacyMappings,
      ))
        m.transaction: m.assignedGroup?.label,
    };
  }

  @override
  void didUpdateWidget(covariant MerchantBaselinePanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.transactions, widget.transactions) ||
        !identical(old.legacyMappings, widget.legacyMappings)) {
      _prepare();
      _indexCache = null;
      _summaryCache.clear();
      if (_changed.isEmpty && !_saving) {
        _draft = {
          for (final r in widget.store.records.values)
            r['id'] as String: Map<String, dynamic>.from(r),
        };
        _refreshClassification(widget.store.index);
      }
    }
  }

  Map<String, dynamic>? _rule(FavouriteSpendingSpot group) {
    if (_summaryCache.containsKey(group.key)) return _summaryCache[group.key];
    final direct = _draft['m:${group.key}'];
    if (direct != null && direct['deleted'] != true)
      return _summaryCache[group.key] = direct;
    final index = _index;
    final found = {
      for (final t in group.transactions)
        if (index.merchantFor(t.transaction.description) case final r?)
          r['id']: r,
    };
    return _summaryCache[group.key] = found.length == 1
        ? found.values.single
        : null;
  }

  final _summaryCache = <String, Map<String, dynamic>?>{};
  String? _type(FavouriteSpendingSpot group) {
    final saved = _rule(group)?['expenseType'];
    if (saved != null) return ExpenseType.parse(saved).sheetValue;
    final types = group.transactions
        .map((t) => t.transaction.expenseType.sheetValue)
        .toSet();
    return types.length == 1 ? types.single : null;
  }

  Widget _typeSelector(
    String key,
    String? value,
    ValueChanged<String> changed, {
    bool inherit = false,
  }) => DropdownButton<String>(
    key: ValueKey(key),
    value: value,
    isExpanded: true,
    hint: const Text('Mixed'),
    items: [
      if (inherit)
        const DropdownMenuItem(
          value: '__inherit',
          child: Text('Use merchant choice'),
        ),
      for (final t in ExpenseType.values)
        DropdownMenuItem(
          value: t.sheetValue,
          child: Text(
            t.sheetValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: _saving
        ? null
        : (v) {
            if (v != null) changed(v);
          },
  );

  String? _category(FavouriteSpendingSpot group) {
    final rule = _rule(group);
    if (rule?['categoryId'] != null) return rule!['categoryId'] as String;
    final ids = {
      for (final t in group.transactions)
        widget.categories
            .where(
              (c) =>
                  c.id == t.transaction.categoryId ||
                  c.name == t.transaction.category,
            )
            .firstOrNull
            ?.id,
    };
    return ids.length == 1 ? ids.single : null;
  }

  String? _group(FavouriteSpendingSpot group) {
    final rule = _rule(group);
    if (rule?['group'] != null) return rule!['group'] as String;
    final values = {
      for (final t in group.transactions)
        _legacy[t.transaction] ?? 'Unclassified',
    };
    return values.length == 1 ? values.single : null;
  }

  void _persistDraft() {
    final changes = [
      for (final id in _changed) Map<String, dynamic>.from(_draft[id]!),
    ];
    unawaited(
      widget.store.saveDraft(changes).catchError((Object error) {
        if (mounted)
          setState(() => _status = 'Could not keep the local draft: $error');
      }),
    );
  }

  Future<void> _discardDraft() async {
    setState(() => _saving = true);
    try {
      await widget.store.clearDraft();
      if (mounted) {
        setState(() {
          _draft = {
            for (final r in widget.store.records.values)
              r['id'] as String: Map<String, dynamic>.from(r),
          };
          _changed.clear();
          _indexCache = null;
          _summaryCache.clear();
          _status = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Could not discard: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setMerchant(
    FavouriteSpendingSpot group, {
    String? categoryId,
    String? lifestyle,
    String? expenseType,
  }) {
    final existing = _rule(group);
    final id = 'm:${group.key}';
    final aliases = {
      for (final t in group.transactions) t.transaction.description,
      ...?((existing?['aliases'] as List?)?.cast<String>()),
    };
    // Reuse saved aliases if grouping labels changed; never leave two competing defaults.
    final fingerprints = aliases
        .map(merchantClassificationKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    for (final r in _draft.values.toList()) {
      if (r['kind'] != 'merchant' || r['deleted'] == true || r['id'] == id)
        continue;
      if ((r['aliases'] as List? ?? []).any(
        (a) => fingerprints.contains(merchantClassificationKey(a.toString())),
      )) {
        aliases.addAll((r['aliases'] as List).cast<String>());
        _draft[r['id'] as String] = {...r, 'deleted': true};
        _changed.add(r['id'] as String);
      }
    }
    final chosenId = categoryId ?? _category(group);
    final category = widget.categories
        .where((c) => c.id == chosenId)
        .firstOrNull;
    _draft[id] = {
      'id': id,
      'kind': 'merchant',
      'name': group.name,
      'aliases': aliases
          .map(merchantClassificationKey)
          .where((key) => key.isNotEmpty)
          .map((key) => key.startsWith('RAW:') ? key.substring(4) : key)
          .toSet()
          .toList(),
      'categoryId': category?.id,
      'category': category?.name,
      'group': lifestyle ?? _group(group),
      'expenseType': expenseType ?? existing?['expenseType'],
    };
    // A merchant edit replaces only the edited fields on existing exceptions.
    for (final item in group.transactions) {
      final key = 't:${item.transaction.id}';
      final previous = _draft[key];
      if (previous == null || previous['deleted'] == true) continue;
      final next = {...previous};
      if (categoryId != null) {
        next.remove('category');
        next.remove('categoryId');
      }
      if (lifestyle != null) next.remove('group');
      // Explicit Expense Type exceptions retain precedence over merchant edits.
      next['deleted'] =
          next['categoryId'] == null &&
          next['group'] == null &&
          next['expenseType'] == null;
      _draft[key] = next;
      _changed.add(key);
    }
    _changed.add(id);
    _status = null;
    _indexCache = null;
    _summaryCache.clear();
    _persistDraft();
  }

  void _setException(
    Transaction t, {
    String? categoryId,
    String? lifestyle,
    String? expenseType,
  }) {
    if (t.id == null) return;
    final id = 't:${t.id}';
    final previous = _draft[id];
    final record = previous?['deleted'] == true
        ? <String, dynamic>{}
        : {...?previous};
    record.addAll({'id': id, 'kind': 'transaction', 'transactionId': t.id});
    if (categoryId != null) {
      final category = widget.categories
          .where((c) => c.id == categoryId)
          .firstOrNull;
      record['categoryId'] = category?.id;
      record['category'] = category?.name;
    }
    if (lifestyle != null)
      record['group'] = lifestyle == '__inherit' ? null : lifestyle;
    if (expenseType != null)
      record['expenseType'] = expenseType == '__inherit' ? null : expenseType;
    record['deleted'] =
        record['categoryId'] == null &&
        record['group'] == null &&
        record['expenseType'] == null;
    _draft[id] = record;
    _changed.add(id);
    _status = null;
    _indexCache = null;
    _summaryCache.clear();
    _persistDraft();
  }

  Future<void> _resetExceptions(FavouriteSpendingSpot group) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace transaction exceptions?'),
        content: Text(
          'Apply the merchant choices to every transaction under ${group.name}, including individual exceptions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply to all'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _setMerchant(group);
      for (final entry in group.transactions) {
        final id = 't:${entry.transaction.id}';
        if (_draft[id] != null) {
          _draft[id] = {..._draft[id]!, 'deleted': true};
          _changed.add(id);
          _indexCache = null;
          _summaryCache.clear();
        }
      }
    });
    _persistDraft();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final changes = [
      for (final id in _changed) Map<String, dynamic>.from(_draft[id]!),
    ];
    try {
      final message = await widget.onSaved(changes);
      await widget.store.clearDraft();
      if (mounted)
        setState(() {
          _refreshClassification(_index);
          _changed.clear();
          _status = message;
        });
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _categorySelector(
    String key,
    String? selected,
    ValueChanged<String> onChanged, {
    bool inherit = false,
  }) {
    final categories = widget.categories
        .where((c) => c.active && !c.archived)
        .toList();
    if (!categories.any((c) => c.id == selected)) selected = null;
    return DropdownButton<String>(
      key: ValueKey(key),
      value: selected,
      isExpanded: true,
      hint: Text(inherit ? 'Use merchant choice' : 'Category / mixed'),
      items: [
        if (inherit)
          const DropdownMenuItem(
            value: '__inherit',
            child: Text('Use merchant choice'),
          ),
        for (final c in categories)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving
          ? null
          : (v) {
              if (v != null) onChanged(v);
            },
    );
  }

  Widget _groupSelector(
    String key,
    String? selected,
    ValueChanged<String> onChanged, {
    bool inherit = false,
  }) => DropdownButton<String>(
    key: ValueKey(key),
    value: selected,
    isExpanded: true,
    hint: Text(inherit ? 'Use merchant choice' : 'Essentiality / mixed'),
    items: [
      if (inherit)
        const DropdownMenuItem(
          value: '__inherit',
          child: Text('Use merchant choice'),
        ),
      for (final s in ['Essential', 'Potentially Flexible', 'Unclassified'])
        DropdownMenuItem(
          value: s,
          child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _saving
        ? null
        : (v) {
            if (v != null) onChanged(v);
          },
  );
  Widget _mobileField(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: DropdownButtonHideUnderline(child: child),
    ),
  );

  Widget _mobileMerchant(FavouriteSpendingSpot group, double total) {
    final isNa = _rule(group)?['na'] == true;
    final opened = _expanded.contains(group.key);
    return Card(
      key: ValueKey('mobile-merchant-${group.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: ValueKey('merchant-expand-${group.key}'),
                  tooltip: 'View transactions',
                  onPressed: () => setState(() {
                    opened
                        ? _expanded.remove(group.key)
                        : _expanded.add(group.key);
                  }),
                  icon: Icon(opened ? Icons.expand_less : Icons.expand_more),
                ),
                Expanded(
                  child: Text(
                    '${group.name} · ${group.transactionCount}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _merchantActions(group, isNa),
              ],
            ),
            Text(
              '${money(group.total)} · ${total <= 0 ? '0.0' : (group.total / total * 100).toStringAsFixed(1)}% of spending',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!_classifiedKeys.contains(group.key) &&
                _complete(group, _index))
              const Text('Ready to save', style: TextStyle(fontSize: 11)),
            _mobileField(
              'Category',
              isNa
                  ? const Text('NA')
                  : _categorySelector(
                      'merchant-category-${group.key}',
                      _category(group),
                      (v) => setState(() => _setMerchant(group, categoryId: v)),
                    ),
            ),
            _mobileField(
              'Essentiality',
              isNa
                  ? const Text('NA')
                  : _groupSelector(
                      'merchant-group-${group.key}',
                      _group(group),
                      (v) => setState(() => _setMerchant(group, lifestyle: v)),
                    ),
            ),
            _mobileField(
              'Expense Type',
              isNa
                  ? const Text('NA')
                  : _typeSelector(
                      'merchant-type-${group.key}',
                      _type(group),
                      (v) =>
                          setState(() => _setMerchant(group, expenseType: v)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileTransaction(Transaction t) {
    final override = _draft['t:${t.id}'];
    final active = override?['deleted'] == true ? null : override;
    final effective = _index.apply(t);
    final isNa = _index.merchantFor(t.description)?['na'] == true;
    return Card(
      key: ValueKey('merchant-transaction-${t.id}'),
      margin: const EdgeInsets.only(left: 12, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.dateOnlyIsoString} · ${money(t.amount)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${active == null ? '' : 'Exception · '}${t.description}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (t.id == null)
              const Text('Sync once to edit')
            else ...[
              _mobileField(
                'Category',
                isNa && active?['category'] == null
                    ? const Text('NA')
                    : _categorySelector(
                        'transaction-category-${t.id}',
                        effective.categoryId,
                        (v) => setState(() => _setException(t, categoryId: v)),
                        inherit: true,
                      ),
              ),
              _mobileField(
                'Essentiality',
                isNa && active?['group'] == null
                    ? const Text('NA')
                    : _groupSelector(
                        'transaction-group-${t.id}',
                        effective.baselineGroup ?? _legacy[t] ?? 'Unclassified',
                        (v) => setState(() => _setException(t, lifestyle: v)),
                        inherit: true,
                      ),
              ),
              _mobileField(
                'Expense Type',
                isNa && active?['expenseType'] == null
                    ? const Text('NA')
                    : _typeSelector(
                        'transaction-type-${t.id}',
                        effective.expenseType.sheetValue,
                        (v) => setState(() => _setException(t, expenseType: v)),
                        inherit: true,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _merchantActions(FavouriteSpendingSpot group, bool isNa) =>
      PopupMenuButton<String>(
        tooltip: 'Merchant actions',
        enabled: !_saving,
        itemBuilder: (_) => [
          if (isNa)
            const PopupMenuItem(value: 'remove-na', child: Text('Remove NA')),
          PopupMenuItem(
            enabled: !isNa && _category(group) != null && _group(group) != null,
            value: 'confirm',
            child: Text('Confirm shown choices'),
          ),
          PopupMenuItem(
            enabled: !isNa && _category(group) != null && _group(group) != null,
            value: 'reset',
            child: Text('Apply to all, including exceptions'),
          ),
        ],
        onSelected: (action) {
          if (action == 'remove-na') {
            _removeNa(group);
          } else if (action == 'confirm') {
            setState(() => _setMerchant(group));
          } else {
            _resetExceptions(group);
          }
        },
      );

  Widget _merchant(
    FavouriteSpendingSpot group,
    double total, {
    bool mobile = false,
  }) {
    if (mobile) return _mobileMerchant(group, total);
    final opened = _expanded.contains(group.key);
    final isNa = _rule(group)?['na'] == true;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                key: ValueKey('merchant-expand-${group.key}'),
                tooltip: 'View transactions',
                onPressed: () => setState(() {
                  opened
                      ? _expanded.remove(group.key)
                      : _expanded.add(group.key);
                }),
                icon: Icon(opened ? Icons.expand_less : Icons.expand_more),
              ),
              Expanded(
                child: Tooltip(
                  message:
                      '${group.name} · ${group.transactionCount} transactions',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.name} · ${group.transactionCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!_classifiedKeys.contains(group.key) &&
                          _complete(group, _index))
                        const Text(
                          'Ready to save',
                          style: TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 142,
                child: Text(
                  '${money(group.total)} · ${(group.total / total * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 190,
                child: isNa
                    ? const Text('NA')
                    : _categorySelector(
                        'merchant-category-${group.key}',
                        _category(group),
                        (v) =>
                            setState(() => _setMerchant(group, categoryId: v)),
                      ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 184,
                child: isNa
                    ? const Text('NA')
                    : _groupSelector(
                        'merchant-group-${group.key}',
                        _group(group),
                        (v) =>
                            setState(() => _setMerchant(group, lifestyle: v)),
                      ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 190,
                child: isNa
                    ? const Text('NA')
                    : _typeSelector(
                        'merchant-type-${group.key}',
                        _type(group),
                        (v) =>
                            setState(() => _setMerchant(group, expenseType: v)),
                      ),
              ),
              _merchantActions(group, isNa),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _transaction(Transaction t, {bool mobile = false}) {
    if (mobile) return _mobileTransaction(t);
    final override = _draft['t:${t.id}'];
    final active = override?['deleted'] == true ? null : override;
    final effective = _index.apply(t);
    final isNa = _index.merchantFor(t.description)?['na'] == true;
    return SizedBox(
      key: ValueKey('merchant-transaction-${t.id}'),
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 48),
          SizedBox(width: 94, child: Text(t.dateOnlyIsoString)),
          Expanded(
            child: Tooltip(
              message: t.description,
              child: Text(
                '${active == null ? '' : 'Exception · '}${t.description}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(money(t.amount), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: t.id == null
                ? const Text('Sync once to edit')
                : isNa && active?['category'] == null
                ? const Text('NA')
                : Tooltip(
                    message: 'Effective category: ${effective.category}',
                    child: _categorySelector(
                      'transaction-category-${t.id}',
                      effective.categoryId,
                      (v) => setState(() => _setException(t, categoryId: v)),
                      inherit: true,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 184,
            child: t.id == null
                ? const SizedBox()
                : isNa && active?['group'] == null
                ? const Text('NA')
                : Tooltip(
                    message:
                        'Effective essentiality: ${effective.baselineGroup ?? _legacy[t] ?? 'Unclassified'}',
                    child: _groupSelector(
                      'transaction-group-${t.id}',
                      effective.baselineGroup ?? _legacy[t] ?? 'Unclassified',
                      (v) => setState(() => _setException(t, lifestyle: v)),
                      inherit: true,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: t.id == null
                ? Text(effective.expenseType.sheetValue)
                : isNa && active?['expenseType'] == null
                ? const Text('NA')
                : _typeSelector(
                    'transaction-type-${t.id}',
                    effective.expenseType.sheetValue,
                    (v) => setState(() => _setException(t, expenseType: v)),
                    inherit: true,
                  ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _reviewEntries(
    List<Object> entries,
    double total, {
    bool mobile = false,
  }) => Builder(
    builder: (context) {
      final parentScroll = Scrollable.maybeOf(context, axis: Axis.vertical);
      return NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 || parentScroll == null) return false;
          // Hand unused drag distance to the page so its section headers remain reachable.
          final position = parentScroll.position;
          final offset = (position.pixels + notification.overscroll).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          if (offset != position.pixels) position.jumpTo(offset);
          return false;
        },
        child: ListView.builder(
          key: ValueKey(
            mobile ? 'mobile-merchant-list' : 'desktop-merchant-list',
          ),
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemCount: entries.isEmpty ? 1 : entries.length,
          itemBuilder: (_, i) => entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _view == 'classified'
                        ? 'No merchants match these filters. Clear filters or change your search.'
                        : 'No merchants match your search.',
                  ),
                )
              : entries[i] is FavouriteSpendingSpot
              ? _merchant(
                  entries[i] as FavouriteSpendingSpot,
                  total,
                  mobile: mobile,
                )
              : _transaction(entries[i] as Transaction, mobile: mobile),
        ),
      );
    },
  );

  Widget _sectionHeader(
    String section,
    String label,
    Color color,
    int count,
    double amount,
  ) {
    final open = _activeSection == section;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        key: ValueKey(
          section == 'na'
              ? 'review-na'
              : section == 'remaining'
              ? 'baseline-unclassified'
              : 'baseline-$section',
        ),
        onTap: _saving ? null : () => _openSection(section),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'merchant' : 'merchants'} · ${money(amount)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(open ? Icons.expand_more : Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _groups.fold<double>(0, (s, g) => s + g.total);
    final visible = switch (_selection) {
      'Top 15' => _groups.take(15).toList(),
      'All' => _groups,
      _ => merchantsForCoverage(
        _groups,
        double.parse(_selection.replaceAll('%', '')) / 100,
      ),
    };
    final completed = <FavouriteSpendingSpot>[];
    final remaining = <FavouriteSpendingSpot>[];
    for (final group in _groups) {
      if (!_naKeys.contains(group.key))
        (_classifiedKeys.contains(group.key) ? completed : remaining).add(
          group,
        );
    }
    final naGroups = _groups.where((g) => _naKeys.contains(g.key)).toList();
    final remainingAmount = remaining.fold<double>(0, (s, g) => s + g.total);
    final naAmount = naGroups.fold<double>(0, (s, g) => s + g.total);
    final reviewed = completed.fold<double>(0, (sum, g) => sum + g.total);
    final remainingKeys = remaining.map((g) => g.key).toSet();
    final reachedTarget = total > 0 && reviewed / total >= .8;
    double unknownTotal(FavouriteSpendingSpot g) => _unknownAmounts[g.key] ?? 0;
    final unknownGroups =
        _groups
            .where(
              (g) =>
                  _unknownAmounts.containsKey(g.key) &&
                  !_naKeys.contains(g.key),
            )
            .toList()
          ..sort((a, b) => unknownTotal(b).compareTo(unknownTotal(a)));
    final source = _view == 'na'
        ? naGroups
        : _view == 'overview'
        ? <FavouriteSpendingSpot>[]
        : _view == 'unknown'
        ? unknownGroups
        : _view == 'classified'
        ? completed
        : _view == 'remaining'
        ? remaining
        : reachedTarget && !_reviewCoverage
        ? <FavouriteSpendingSpot>[]
        : (_query.trim().isEmpty ? visible : _groups)
              .where((g) => remainingKeys.contains(g.key))
              .toList();
    final filtered = source
        .where(
          (g) =>
              g.name.toLowerCase().contains(_query.toLowerCase()) &&
              _matchesReviewFilters(g),
        )
        .toList();
    final selectedAmount = filtered.fold<double>(0, (sum, g) => sum + g.total);
    final scope = _view == 'focus' && _query.trim().isEmpty
        ? '$_selection${_selection.endsWith('%') ? ' target' : ''}'
        : _view == 'focus' || _view == 'remaining'
        ? 'Unclassified'
        : _view == 'unknown'
        ? 'Unknown Expense Types'
        : _view == 'na'
        ? 'Excluded'
        : 'Classified';
    final equivalent = _view == 'focus' && _query.trim().isEmpty
        ? ['75%', '80%', '90%'].where((option) {
            if (option == _selection) return false;
            final other =
                merchantsForCoverage(
                      _groups,
                      double.parse(option.replaceAll('%', '')) / 100,
                    )
                    .where(
                      (g) =>
                          remainingKeys.contains(g.key) &&
                          _matchesReviewFilters(g),
                    )
                    .map((g) => g.key)
                    .toSet();
            return other.length == filtered.length &&
                filtered.every((g) => other.contains(g.key));
          }).firstOrNull
        : null;
    final entries = <Object>[];
    for (final group in filtered) {
      entries.add(group);
      if (_expanded.contains(group.key)) {
        entries.addAll(group.transactions.map((item) => item.transaction));
      }
    }
    final dates = widget.transactions.map((t) => t.date).toList()..sort();
    final classifiedPercent = total == 0
        ? 0.0
        : (reviewed / total * 100).clamp(0.0, 100.0);
    final historyPeriod = dates.isEmpty
        ? null
        : '${dates.first.toIso8601String().split('T').first} to '
              '${dates.last.toIso8601String().split('T').first}';
    final showReview = _merchantsExpanded && _view != 'overview';
    final showNaAction =
        (_view == 'remaining' || _view == 'focus') &&
        remaining.any((group) => group.total >= 100);
    final showTable = showReview && source.isNotEmpty;
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final sections = [
      (
        'classified',
        'Classified',
        theme.colorScheme.primary,
        completed.length,
        reviewed,
      ),
      (
        'remaining',
        'Unclassified',
        semantic.warning,
        remaining.length,
        remainingAmount,
      ),
      ('na', 'Excluded', theme.colorScheme.outline, naGroups.length, naAmount),
    ];
    return LayoutBuilder(
      builder: (context, panelConstraints) {
        final panel = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Financial Baseline',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'How coverage is calculated',
                      onPressed: () =>
                          _showCoverageDetails(sections, total, historyPeriod),
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    Text(
                      '${classifiedPercent.toStringAsFixed(1)}%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'of spending classified',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      key: const ValueKey('baseline-spending-bar'),
                      children: [
                        if (total <= 0)
                          Container(
                            width: constraints.maxWidth,
                            height: 12,
                            color: theme.colorScheme.surfaceContainerHighest,
                          )
                        else
                          for (final section in sections)
                            if (section.$5 > 0)
                              Tooltip(
                                message:
                                    '${section.$2}: ${(section.$5 / total * 100).toStringAsFixed(1)}%',
                                child: Container(
                                  key: ValueKey('baseline-bar-${section.$1}'),
                                  width:
                                      constraints.maxWidth * section.$5 / total,
                                  height: 12,
                                  color: section.$3,
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final section in sections)
                      Tooltip(
                        message:
                            '${section.$2}: ${(total <= 0 ? 0.0 : section.$5 / total * 100).toStringAsFixed(1)}%',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 10, color: section.$3),
                            const SizedBox(width: 5),
                            Text(section.$2, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                  ],
                ),
                for (final section in sections) ...[
                  const Divider(height: 24),
                  _sectionHeader(
                    section.$1,
                    section.$2,
                    section.$3,
                    section.$4,
                    section.$5,
                  ),
                  if (_activeSection == section.$1)
                    SizedBox(
                      height: showTable
                          ? ((showNaAction && _showNaControls) ||
                                            (_view == 'classified' &&
                                                _filtersOpen)
                                        ? MediaQuery.sizeOf(context).height *
                                              1.2
                                        : (MediaQuery.sizeOf(context).width <
                                                  600
                                              ? MediaQuery.sizeOf(context)
                                                        .height *
                                                    1.15
                                              : MediaQuery.sizeOf(context)
                                                        .height *
                                                    .78))
                                    .clamp(620.0, 1100.0) +
                                (showNaAction ? 100 : 0)
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_merchantsExpanded) ...[
                            const SizedBox(height: 12),
                            if (!widget.historyComplete)
                              const Text(
                                'Showing saved history while syncing.',
                              ),
                            if (showNaAction)
                              Card(
                                key: const ValueKey('bulk-exclusion-box'),
                                margin: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 24,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _naControls(),
                                ),
                              ),
                            if (_view == 'remaining' || _view == 'focus')
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final option in [
                                      'Top 15',
                                      '75%',
                                      '80%',
                                      '90%',
                                      'All',
                                    ])
                                      ChoiceChip(
                                        label: Text(option),
                                        selected: _selection == option,
                                        onSelected: (_) => setState(() {
                                          _selection = option;
                                          _view = 'focus';
                                          _reviewCoverage = true;
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                            if (_view == 'overview')
                              const Text('Choose a group to view merchants.'),
                            if (showReview) ...[
                              const SizedBox(height: 8),
                              Text(
                                '$scope · ${filtered.length} merchants · ${money(selectedAmount)} · ${(total <= 0 ? 0.0 : selectedAmount / total * 100).toStringAsFixed(1)}% of spending',
                                key: const ValueKey('merchant-coverage-scope'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (_query.trim().isNotEmpty && _view == 'focus')
                                const Text(
                                  'Search includes all unclassified merchants, beyond the coverage target.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              if (equivalent != null && filtered.isNotEmpty)
                                Text(
                                  'Same ${filtered.length} merchants as the $equivalent selection.',
                                  key: const ValueKey(
                                    'merchant-coverage-equivalent',
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              const SizedBox(height: 8),
                            ],
                            if (_view == 'unknown')
                              Text(
                                'Unknown Expense Types (${unknownGroups.length}) · largest spending first.',
                                style: TextStyle(fontSize: 12),
                              ),
                            if (showReview) const SizedBox(height: 16),
                            if (showTable) ...[
                              if (_view == 'classified' && _filtersOpen)
                                _reviewFilters(),
                              if (_view == 'classified' && _filterCount > 0)
                                Text(
                                  '${filtered.length} of ${source.length} merchants match · changes update these results after saving',
                                  key: const ValueKey(
                                    'baseline-filter-results',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              SizedBox(
                                height: 42,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        key: ValueKey(
                                          'baseline-search-' + _view,
                                        ),
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.search),
                                          hintText:
                                              'Search merchants in this view',
                                          isDense: true,
                                        ),
                                        onChanged: (s) =>
                                            setState(() => _query = s),
                                      ),
                                    ),
                                    if (_view == 'classified')
                                      TextButton.icon(
                                        key: const ValueKey(
                                          'baseline-filter-toggle',
                                        ),
                                        onPressed: () => setState(
                                          () => _filtersOpen = !_filtersOpen,
                                        ),
                                        icon: const Icon(Icons.filter_list),
                                        label: Text(
                                          _filterCount == 0
                                              ? 'Filters'
                                              : 'Filters ($_filterCount)',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (_, constraints) =>
                                      constraints.maxWidth < 1140
                                      ? _reviewEntries(
                                          entries,
                                          total,
                                          mobile: true,
                                        )
                                      : SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: constraints.maxWidth < 1140
                                                ? 1140
                                                : constraints.maxWidth,
                                            child: Column(
                                              children: [
                                                if (entries.isNotEmpty)
                                                  const SizedBox(
                                                    height: 28,
                                                    child: Row(
                                                      children: [
                                                        SizedBox(width: 48),
                                                        Expanded(
                                                          child: Text(
                                                            'Merchant',
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 154,
                                                          child: Text(
                                                            'Spending / coverage',
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 202,
                                                          child: Text(
                                                            'Category',
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 184,
                                                          child: Text(
                                                            'Essentiality',
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 202,
                                                          child: Text(
                                                            'Expense Type',
                                                          ),
                                                        ),
                                                        SizedBox(width: 48),
                                                      ],
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: _reviewEntries(
                                                    entries,
                                                    total,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                            if (showReview && !showTable)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  _view == 'classified'
                                      ? 'No classified merchants yet.'
                                      : _view == 'na'
                                      ? 'No merchants marked NA.'
                                      : 'No unclassified merchants in this selection.',
                                ),
                              ),
                            if (_status != null)
                              Text(
                                _status!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (_changed.isNotEmpty)
                              Text(
                                '$_changedMerchantCount ${_changedMerchantCount == 1 ? 'merchant has' : 'merchants have'} unsaved changes · save to update classification progress',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (showReview || _changed.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if (_changed.isNotEmpty)
                                      TextButton(
                                        onPressed: _saving
                                            ? null
                                            : _discardDraft,
                                        child: const Text('Discard'),
                                      ),
                                    FilledButton(
                                      onPressed: _changed.isEmpty || _saving
                                          ? null
                                          : _save,
                                      child: Text(
                                        _saving ? 'Saving…' : 'Save changes',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MerchantDesktopSuggestion(
              store: widget.store,
              merchantsNeedingReview: remaining.length,
              hasUnsavedChanges: _changed.isNotEmpty,
            ),
            if (panelConstraints.hasBoundedHeight)
              Expanded(child: SingleChildScrollView(child: panel))
            else
              panel,
          ],
        );
      },
    );
  }
}
