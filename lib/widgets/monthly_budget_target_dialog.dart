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
    this.unknownCount = 0,
    this.onReviewUnclassified,
  });

  final String currencySymbol;
  final double? initialTarget;
  final SuggestedBudget? suggestion;
  final int unknownCount;
  final VoidCallback? onReviewUnclassified;

  @override
  State<MonthlyBudgetTargetDialog> createState() =>
      _MonthlyBudgetTargetDialogState();
}

class _MonthlyBudgetTargetDialogState extends State<MonthlyBudgetTargetDialog> {
  static final _groupedAmount = RegExp(
    r'^(?:\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})*,\d{3})(?:\.\d*)?$',
  );
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialTarget == null
          ? ''
          : _formattedInput(widget.initialTarget!),
    );
  }

  String _formattedInput(double amount) => formatFullCurrency(
    amount,
    widget.currencySymbol,
  ).substring(widget.currencySymbol.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveTarget() {
    final input = _controller.text.trim();
    final amount = input.contains(',') && !_groupedAmount.hasMatch(input)
        ? null
        : double.tryParse(input.replaceAll(',', ''));
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _validationError = 'Enter a target greater than zero.');
      return;
    }

    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final linkStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        decoration: TextDecoration.underline,
      ),
    );
    return AlertDialog(
      title: const Text('Set Monthly Target', textAlign: TextAlign.center),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: theme.textTheme.headlineSmall,
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Monthly spending limit',
                  prefixText: widget.currencySymbol,
                  errorText: _validationError,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.unknownCount > 0) ...[
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${widget.unknownCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ' unclassified ${widget.unknownCount == 1 ? 'expense' : 'expenses'} detected. Budget suggestions may refine after categorization.',
                      ),
                    ],
                  ),
                  key: const ValueKey('budget-classification-note'),
                ),
              ],
              if (widget.unknownCount > 0 &&
                  widget.onReviewUnclassified != null)
                TextButton(
                  onPressed: widget.onReviewUnclassified,
                  style: linkStyle,
                  child: const Text('Classify remaining expenses'),
                ),
              if (widget.suggestion != null) ...[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('suggested-budget-panel'),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        key: const ValueKey('suggested-budget-dialog-card'),
                        onTap: () async {
                          await showSuggestedBudgetSheet(
                            context: context,
                            suggestion: widget.suggestion!,
                            currencySymbol: widget.currencySymbol,
                            allowApply: false,
                            onReviewUnclassified: widget.onReviewUnclassified,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Suggested: ${formatFullCurrency(widget.suggestion!.amount, widget.currencySymbol)}',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _controller.text = _formattedInput(
                            widget.suggestion!.amount,
                          );
                          setState(() => _validationError = null);
                        },
                        style: linkStyle,
                        child: const Text('Use suggested amount'),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.suggestion == null)
                const Text(
                  'Not enough eligible Regular spending history to suggest a budget yet.',
                ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saveTarget,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Save Target'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
