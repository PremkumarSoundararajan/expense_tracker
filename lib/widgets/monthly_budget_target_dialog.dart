import 'package:flutter/material.dart';

import '../services/suggested_budget_service.dart';
import '../utils/currency_format.dart';
import 'suggested_budget_sheet.dart';

class MonthlyBudgetTargetDialog extends StatefulWidget {
  const MonthlyBudgetTargetDialog({
    super.key,
    required this.currencySymbol,
    required this.initialTarget,
    this.suggestion,
  });

  final String currencySymbol;
  final double? initialTarget;
  final SuggestedBudget? suggestion;

  @override
  State<MonthlyBudgetTargetDialog> createState() =>
      _MonthlyBudgetTargetDialogState();
}

class _MonthlyBudgetTargetDialogState extends State<MonthlyBudgetTargetDialog> {
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialTarget?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveTarget() {
    final amount = double.tryParse(_controller.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _validationError = 'Enter a target greater than zero.');
      return;
    }

    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Monthly Target'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Monthly spending limit',
              prefixText: '${widget.currencySymbol} ',
              errorText: _validationError,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.suggestion != null) ...[
            const SizedBox(height: 12),
            InkWell(
              key: const ValueKey('suggested-budget-dialog-card'),
              onTap: () async {
                await showSuggestedBudgetSheet(
                  context: context,
                  suggestion: widget.suggestion!,
                  currencySymbol: widget.currencySymbol,
                  allowApply: false,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Suggested ${formatFullCurrency(widget.suggestion!.amount, widget.currencySymbol)} · tap to see how it was calculated',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _controller.text = widget.suggestion!.amount.toStringAsFixed(
                  2,
                );
                setState(() => _validationError = null);
              },
              child: const Text('Use suggested amount'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saveTarget, child: const Text('Save Target')),
      ],
    );
  }
}
