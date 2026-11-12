import 'dart:async';

import 'package:flutter/material.dart';

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
  });
  final List<Transaction> transactions;
  final List<ExpenseCategory> categories;
  final List<FinancialBaselineMapping> legacyMappings;
  final MerchantClassificationStore store;
  final String currencySymbol;
  final bool historyComplete;
  final bool showRemainingInitially;
  final bool reviewUnknownInitially;
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
  Widget _reviewButton(
    String view,
    String label,
    int count,
    double percent,
    IconData icon,
  ) {
    final selected = view == 'remaining'
        ? ['remaining', 'unknown', 'focus'].contains(_view)
        : _view == view;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          key: ValueKey(
            'baseline-' + (view == 'remaining' ? 'unclassified' : 'classified'),
          ),
          onPressed: () => setState(() {
            if (_view != view) _query = '';
            _view = view;
            _reviewCoverage = false;
            if (view == 'remaining') _selection = 'All';
          }),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected
                ? colors.primaryContainer
                : colors.surface,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(
                label + ' (' + count.toString() + ')',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                percent.toStringAsFixed(1) + '% of spending',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.showRemainingInitially) _view = 'remaining';
    if (widget.reviewUnknownInitially) _view = 'unknown';
    _draft = {
      for (final r in widget.store.records.values)
        r['id'] as String: Map<String, dynamic>.from(r),
    };
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
    if (preview.groups.isEmpty) {
      setState(
        () => _naError = 'No unclassified merchants have a positive total below this amount.',
      );
      return;
    }
    final index = _index;
    setState(() {
      _naError = null;
      for (final group in preview.groups) {
        final record = merchantNaRecord(group, index);
        _draft[record['id'] as String] = record;
        _changed.add(record['id'] as String);
      }
      _indexCache = null;
      _summaryCache.clear();
      _persistDraft();
    });
    await _save();
    if (mounted && _changed.isEmpty)
      setState(() {
        _view = 'na';
        _query = '';
        _showNaControls = false;
      });
  }

  MerchantNaPreview _unclassifiedNaPreview(double threshold) {
    final preview = previewMerchantNa(_groups, threshold);
    return MerchantNaPreview(
      preview.groups
          .where(
            (g) => !_classifiedKeys.contains(g.key) && !_naKeys.contains(g.key),
          )
          .toList(),
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
          const Text(
            'For unclassified merchants with total recorded expenses less than:',
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
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
                    errorText: _naError,
                  ),
                  onChanged: (_) => setState(() => _naError = null),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('save-na-threshold'),
                onPressed: _saving ? null : _applyNa,
                child: const Text('Exclude'),
              ),
            ],
          ),
          if (preview != null)
            Text(
              '${preview.groups.length} merchants · ${preview.transactions} transactions · ${money(preview.amount)} (${preview.spendingPercent.toStringAsFixed(1)}% of total spending) would be excluded.',
              style: const TextStyle(fontSize: 12),
            ),
          if (preview != null && preview.transactionPercent > 25)
            Text(
              'This marks ${preview.transactionPercent.toStringAsFixed(1)}% of transactions NA (over 25%) and may affect insights.',
              key: const ValueKey('na-impact-warning'),
              style: const TextStyle(fontSize: 12),
            ),
          const Text(
            'Marks all three classifications NA and moves these merchants to Excluded. Spending stays in totals and budgets; transaction exceptions are preserved. Future transactions inherit the merchant choice.',
            style: TextStyle(fontSize: 11),
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
    await widget.store.clearDraft();
    if (mounted)
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
    return Container(
      key: ValueKey('mobile-merchant-${group.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
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
          if (!_classifiedKeys.contains(group.key) && _complete(group, _index))
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
                    (v) => setState(() => _setMerchant(group, expenseType: v)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mobileTransaction(Transaction t) {
    final override = _draft['t:${t.id}'];
    final active = override?['deleted'] == true ? null : override;
    final effective = _index.apply(t);
    final isNa = _index.merchantFor(t.description)?['na'] == true;
    return Container(
      key: ValueKey('merchant-transaction-${t.id}'),
      margin: const EdgeInsets.only(left: 12, bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
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
  }) => ListView.builder(
    key: ValueKey(mobile ? 'mobile-merchant-list' : 'desktop-merchant-list'),
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
        ? _merchant(entries[i] as FavouriteSpendingSpot, total, mobile: mobile)
        : _transaction(entries[i] as Transaction, mobile: mobile),
  );

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
    final coverageSummary =
        '${classifiedPercent.toStringAsFixed(1)}% classified · ${(total <= 0 ? 0.0 : remainingAmount / total * 100).toStringAsFixed(1)}% unclassified${naGroups.isEmpty ? '' : ' · ' + (total <= 0 ? 0.0 : naAmount / total * 100).toStringAsFixed(1) + '% NA'}';
    final showReview = _view != 'overview';
    final showNaAction = _view == 'remaining' || _view == 'focus';
    final showTable = showReview && source.isNotEmpty;
    return LayoutBuilder(
      builder: (context, panelConstraints) {
        final panel = SizedBox(
          height: showTable
              ? ((showNaAction && _showNaControls) ||
                            (_view == 'classified' && _filtersOpen)
                        ? MediaQuery.sizeOf(context).height * 1.2
                        : (MediaQuery.sizeOf(context).width < 600
                              ? MediaQuery.sizeOf(context).height * 1.15
                              : MediaQuery.sizeOf(context).height * .78))
                    .clamp(620.0, 1100.0)
              : null,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Financial Baseline',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Tooltip(
                        message:
                            'Merchant choices apply to all its transactions. Expand a merchant to edit individual transactions.'
                            '${dates.isEmpty ? '' : '\nSpending history: ${dates.first.toIso8601String().split('T').first} to ${dates.last.toIso8601String().split('T').first}'}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.info_outline, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!widget.historyComplete)
                    const Text('Showing saved history while syncing.'),
                  Row(
                    children: [
                      _reviewButton(
                        'classified',
                        'Classified',
                        completed.length,
                        classifiedPercent,
                        Icons.check_circle_outline,
                      ),
                      const SizedBox(width: 8),
                      _reviewButton(
                        'remaining',
                        'Unclassified',
                        remaining.length,
                        total <= 0 ? 0.0 : remainingAmount / total * 100,
                        Icons.pending_actions_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (naGroups.isNotEmpty)
                    TextButton(
                      key: const ValueKey('review-na'),
                      onPressed: () => setState(() {
                        _view = 'na';
                        _query = '';
                      }),
                      child: Text(
                        'Excluded (' +
                            naGroups.length.toString() +
                            ') · ' +
                            (total <= 0 ? 0.0 : naAmount / total * 100)
                                .toStringAsFixed(1) +
                            '% of spending',
                      ),
                    ),
                  if (showNaAction) _naControls(),
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
                  if (_view == 'unknown')
                    Text(
                      'Unknown Expense Types (' +
                          unknownGroups.length.toString() +
                          ') · Largest Unknown spending first. Expand to review transaction exceptions.',
                      style: TextStyle(fontSize: 12),
                    ),
                  if (reachedTarget && _view == 'overview')
                    Text(
                      'Top 80% done. You can stop here, or choose Unclassified above.',
                    ),
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : (reviewed / total).clamp(0, 1),
                  ),
                  if (showTable) ...[
                    if (_view == 'classified' && _filtersOpen) _reviewFilters(),
                    if (_view == 'classified' && _filterCount > 0)
                      Text(
                        '${filtered.length} of ${source.length} merchants match · changes update these results after saving',
                        key: const ValueKey('baseline-filter-results'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    SizedBox(
                      height: 42,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('baseline-search-' + _view),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search merchants in this view',
                                isDense: true,
                              ),
                              onChanged: (s) => setState(() => _query = s),
                            ),
                          ),
                          if (_view == 'classified')
                            TextButton.icon(
                              key: const ValueKey('baseline-filter-toggle'),
                              onPressed: () =>
                                  setState(() => _filtersOpen = !_filtersOpen),
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
                        builder: (_, constraints) => constraints.maxWidth < 1140
                            ? _reviewEntries(entries, total, mobile: true)
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
                                              Expanded(child: Text('Merchant')),
                                              SizedBox(
                                                width: 154,
                                                child: Text(
                                                  'Spending / coverage',
                                                ),
                                              ),
                                              SizedBox(
                                                width: 202,
                                                child: Text('Category'),
                                              ),
                                              SizedBox(
                                                width: 184,
                                                child: Text('Essentiality'),
                                              ),
                                              SizedBox(
                                                width: 202,
                                                child: Text('Expense Type'),
                                              ),
                                              SizedBox(width: 48),
                                            ],
                                          ),
                                        ),
                                      Expanded(
                                        child: _reviewEntries(entries, total),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _view == 'classified'
                            ? 'No classified merchants yet.'
                            : _view == 'na'
                            ? 'No merchants marked NA.'
                            : 'No unclassified merchants in this selection.',
                      ),
                    ),
                  if (showReview)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Category → breakdowns · Expense Type → budgets · Essentiality → savings',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_status != null)
                    Text(
                      _status!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (showReview)
                    Text(
                      coverageSummary,
                      key: const ValueKey('baseline-coverage-summary'),
                    ),
                  if (_changed.isNotEmpty)
                    Text(
                      '${_changed.length} unsaved changes · save to update classification progress',
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
                              onPressed: _saving ? null : _discardDraft,
                              child: const Text('Discard'),
                            ),
                          FilledButton(
                            onPressed: _changed.isEmpty || _saving
                                ? null
                                : _save,
                            child: Text(_saving ? 'Saving…' : 'Save changes'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
              Expanded(child: panel)
            else
              panel,
          ],
        );
      },
    );
  }
}
