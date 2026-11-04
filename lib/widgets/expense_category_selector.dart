import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/transaction.dart';

class ExpenseCategoryOption {
  const ExpenseCategoryOption({required this.name, required this.icon});
  final String name;
  final String icon;
}

const expenseCategoryOptions = [
  ExpenseCategoryOption(name: 'Housing / Bills', icon: '🏠'),
  ExpenseCategoryOption(name: 'Food / Household', icon: '🛒'),
  ExpenseCategoryOption(name: 'Transport', icon: '⛽'),
  ExpenseCategoryOption(name: 'Financial Obligations', icon: '💳'),
  ExpenseCategoryOption(name: 'Health & Wellness', icon: '🩺'),
  ExpenseCategoryOption(name: 'Lifestyle / Misc', icon: '🍿'),
];

class ExpenseCategorySelector extends StatelessWidget {
  const ExpenseCategorySelector({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.categories = const [],
    this.transactions = const [],
  });
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final List<ExpenseCategory> categories;
  final List<Transaction> transactions;

  List<ExpenseCategory> get _options {
    if (categories.isNotEmpty)
      return categories.where((c) => c.active && !c.archived).toList();
    return [
      for (final entry in defaultExpenseParents.entries)
        ExpenseCategory(id: entry.key, parentId: entry.key, name: entry.value),
    ];
  }

  Future<void> _choose(BuildContext context) async {
    final options = _options;
    final now = DateTime.now();
    final recentTransactions =
        transactions.where((t) => now.difference(t.date).inDays <= 180).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final recent = <ExpenseCategory>[];
    for (final tx in recentTransactions) {
      final match = options
          .where((c) => c.name == tx.category || c.id == tx.categoryId)
          .firstOrNull;
      if (match != null && !recent.any((c) => c.id == match.id))
        recent.add(match);
      if (recent.length == 5) break;
    }
    final counts = <String, int>{};
    for (final tx in transactions.where(
      (t) => now.difference(t.date).inDays <= 180,
    )) {
      final id =
          tx.categoryId ??
          options.where((c) => c.name == tx.category).firstOrNull?.id;
      if (id != null) counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    final frequent = options.where((c) => counts.containsKey(c.id)).toList()
      ..sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    final alphabetic = [...options]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selected = await showModalBottomSheet<ExpenseCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CategoryPickerSheet(
        selectedId: options
            .where(
              (c) => c.name == selectedCategory || c.id == selectedCategory,
            )
            .firstOrNull
            ?.id,
        recent: recent,
        frequent: frequent,
        all: alphabetic,
      ),
    );
    if (selected != null) onCategorySelected(selected.name);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _options
        .where((c) => c.name == selectedCategory || c.id == selectedCategory)
        .firstOrNull;
    return OutlinedButton(
      key: const ValueKey('expense-category-selector'),
      onPressed: () => _choose(context),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          const Icon(Icons.category_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected?.name ?? selectedCategory,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (selected != null && selected.parentName != selected.name)
                  Text(
                    selected.parentName,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const Icon(Icons.search),
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.selectedId,
    required this.recent,
    required this.frequent,
    required this.all,
  });
  final String? selectedId;
  final List<ExpenseCategory> recent;
  final List<ExpenseCategory> frequent;
  final List<ExpenseCategory> all;
  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.all
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.parentName.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search categories',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: query.isNotEmpty
                    ? _categoryList(matches)
                    : ListView(
                        children: [
                          if (widget.recent.isNotEmpty) ...[
                            _heading('Recently used'),
                            ..._categoryTiles(widget.recent),
                          ],
                          if (widget.frequent.isNotEmpty) ...[
                            _heading('Frequently used'),
                            ..._categoryTiles(widget.frequent.take(5).toList()),
                          ],
                          _heading('All categories'),
                          ..._categoryTiles(widget.all),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(title, style: Theme.of(context).textTheme.labelLarge),
  );
  Widget _categoryList(List<ExpenseCategory> values) => values.isEmpty
      ? const Center(child: Text('No categories match. Try another search.'))
      : ListView(
          key: const ValueKey('category-options-list'),
          children: _categoryTiles(values),
        );
  List<Widget> _categoryTiles(Iterable<ExpenseCategory> values) => [
    for (final category in values)
      ListTile(
        dense: true,
        title: Text(category.name),
        subtitle: Text(category.parentName),
        trailing: category.id == widget.selectedId
            ? const Icon(Icons.check)
            : null,
        onTap: () => Navigator.of(context).pop(category),
      ),
  ];
}
