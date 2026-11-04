import 'package:flutter/material.dart';

import '../models/expense_category.dart';

class ExpenseCategoryManagementScreen extends StatefulWidget {
  const ExpenseCategoryManagementScreen({
    super.key,
    required this.categories,
    required this.onChanged,
    this.mappings = const [],
    this.onMappingsChanged,
  });
  final List<ExpenseCategory> categories;
  final ValueChanged<List<ExpenseCategory>> onChanged;
  final List<ExpenseCategoryMapping> mappings;
  final ValueChanged<List<ExpenseCategoryMapping>>? onMappingsChanged;
  @override
  State<ExpenseCategoryManagementScreen> createState() =>
      _ExpenseCategoryManagementScreenState();
}

class _ExpenseCategoryManagementScreenState
    extends State<ExpenseCategoryManagementScreen> {
  late List<ExpenseCategory> _items = [...widget.categories];
  late List<ExpenseCategoryMapping> _mappings = [...widget.mappings];
  void _commit() => widget.onChanged(List.unmodifiable(_items));
  List<ExpenseCategory> _under(String parent) =>
      _items.where((c) => c.parentId == parent).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ExpenseCategory> _allUnder(String parentId) {
    final saved = {for (final item in _under(parentId)) item.id: item};
    final suggestions = suggestedExpenseSubcategories[parentId] ?? const <String>[];
    final all = <ExpenseCategory>[
      for (var index = 0; index < suggestions.length; index++)
        saved[stableCategoryId(parentId, suggestions[index])] ?? ExpenseCategory(
          id: stableCategoryId(parentId, suggestions[index]),
          parentId: parentId,
          name: suggestions[index],
          active: false,
          isSuggested: true,
          sortOrder: index,
        ),
      ..._under(parentId).where((item) => !item.isSuggested),
    ];
    return all..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  Future<String?> _askName({String? initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial == null ? 'Add subcategory' : 'Rename subcategory'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _add(String parentId) async {
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    final used = _items.any(
      (c) =>
          c.parentId == parentId && c.name.toLowerCase() == name.toLowerCase(),
    );
    if (used) return;
    setState(
      () => _items.add(
        ExpenseCategory(
          id: createCustomCategoryId(parentId),
          parentId: parentId,
          name: name,
          sortOrder: suggestedExpenseSubcategories[parentId]!.length + _under(parentId).where((item) => !item.isSuggested).length,
        ),
      ),
    );
    _commit();
  }

  Future<void> _rename(ExpenseCategory category) async {
    final name = await _askName(initial: category.name);
    if (name == null || name.isEmpty || name == category.name) return;
    setState(() {
      if (!_items.any((c) => c.id == category.id)) _items.add(category);
      _items = _items
          .map((c) => c.id == category.id ? c.copyWith(name: name) : c)
          .toList();
    });
    _commit();
  }

  void _move(ExpenseCategory category, int delta) {
    final siblings = _allUnder(category.parentId);
    final index = siblings.indexWhere((c) => c.id == category.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    final moving = siblings.removeAt(index);
    siblings.insert(target, moving);
    setState(() {
      _items.removeWhere((c) => c.parentId == category.parentId);
      _items.addAll([for (var i = 0; i < siblings.length; i++) siblings[i].copyWith(sortOrder: i)]);
    });
    _commit();
  }
  void _toggle(ExpenseCategory category, bool enabled) {
    setState(
      () => _items = _items
          .map(
            (c) => c.id == category.id
                ? c.copyWith(active: enabled, archived: !enabled)
                : c,
          )
          .toList(),
    );
    _commit();
  }

  Future<void> _addMapping() async {
    final active = _items.where((c) => c.active && !c.archived).toList();
    if (active.isEmpty) return;
    final keywordController = TextEditingController();
    var selectedId = active.first.id;
    var exact = false;
    final mapping = await showDialog<ExpenseCategoryMapping>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add category rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keywordController,
                decoration: const InputDecoration(
                  labelText: 'Description or keyword',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: active
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedId = value);
                },
              ),
              SwitchListTile(
                title: const Text('Match full description exactly'),
                value: exact,
                onChanged: (value) => setDialogState(() => exact = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = keywordController.text.trim();
                if (value.isNotEmpty)
                  Navigator.pop(
                    context,
                    ExpenseCategoryMapping(
                      keyword: value,
                      categoryId: selectedId,
                      matchType: exact ? 'exact' : 'keyword',
                    ),
                  );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    keywordController.dispose();
    if (mapping == null) return;
    setState(() => _mappings.add(mapping));
    widget.onMappingsChanged?.call(List.unmodifiable(_mappings));
  }

  void _deleteMapping(ExpenseCategoryMapping mapping) {
    setState(() => _mappings.remove(mapping));
    widget.onMappingsChanged?.call(List.unmodifiable(_mappings));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expense categories')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Choose the subcategories you use. Archived categories remain attached to existing transactions and can be restored.',
        ),
        const SizedBox(height: 12),
        for (final parent in defaultExpenseParents.entries)
          Card(
            child: ExpansionTile(
              key: PageStorageKey(parent.key),
              title: Text(parent.value),
              subtitle: Text(
                '${_under(parent.key).where((c) => c.active && !c.archived).length} active',
              ),
              children: [
                for (final category in _allUnder(parent.key))
                  category.isSuggested ? _suggestion(category) : _categoryTile(category),                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _add(parent.key),
                    icon: const Icon(Icons.add),
                    label: const Text('Add custom'),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Import category rules',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Save merchant keywords so statement imports can reuse your category choices.',
        ),
        for (final mapping in _mappings)
          ListTile(
            dense: true,
            title: Text(mapping.keyword),
            subtitle: Text(
              '${_items.where((c) => c.id == mapping.categoryId).firstOrNull?.name ?? 'Archived category'} · ${mapping.matchType == 'exact' ? 'exact' : 'keyword'}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete rule',
              onPressed: () => _deleteMapping(mapping),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addMapping,
            icon: const Icon(Icons.add),
            label: const Text('Add keyword rule'),
          ),
        ),
        if (_items.any((c) => c.archived)) ...[
          const SizedBox(height: 8),
          Text('Archived', style: Theme.of(context).textTheme.titleMedium),
          for (final item in _items.where((c) => c.archived))
            ListTile(
              title: Text(item.name),
              subtitle: Text(item.parentName),
              trailing: TextButton(
                onPressed: () => _toggle(item, true),
                child: const Text('Restore'),
              ),
            ),
        ],
      ],
    ),
  );

  Widget _suggestion(ExpenseCategory category) => ListTile(
    dense: true,
    leading: Checkbox(
      value: category.active && !category.archived,
      onChanged: (value) {
        final updated = category.copyWith(active: value ?? false, archived: false);
        setState(() {
          final index = _items.indexWhere((item) => item.id == category.id);
          if (index < 0) _items.add(updated); else _items[index] = updated;
        });
        _commit();
      },
    ),
    title: Text(category.name),
    trailing: Wrap(spacing: 0, children: [
      IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward), onPressed: () => _move(category, -1)),
      IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward), onPressed: () => _move(category, 1)),
      IconButton(tooltip: 'Rename subcategory', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(category)),
    ]),
  );
  Widget _categoryTile(ExpenseCategory category) => ListTile(
    dense: true,
    title: Text(category.name),
    trailing: Wrap(
      spacing: 0,
      children: [
        IconButton(
          tooltip: 'Move up',
          icon: const Icon(Icons.arrow_upward),
          onPressed: () => _move(category, -1),
        ),
        IconButton(
          tooltip: 'Move down',
          icon: const Icon(Icons.arrow_downward),
          onPressed: () => _move(category, 1),
        ),
        IconButton(
          tooltip: 'Rename',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _rename(category),
        ),
        Switch(
          value: category.active && !category.archived,
          onChanged: (value) => _toggle(category, value),
        ),
      ],
    ),
  );
}

