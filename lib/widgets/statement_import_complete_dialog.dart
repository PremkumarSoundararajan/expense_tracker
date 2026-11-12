import 'package:flutter/material.dart';

class StatementImportCompleteDialog extends StatelessWidget {
  const StatementImportCompleteDialog({super.key, required this.summary});
  final String summary;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Statement imported'),
    content: Text(
      '$summary\n\nNext: classify merchants once in Financial Baseline. Your choices apply to their transactions and future imports. You can edit individual exceptions anytime.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Done for now'),
      ),
      FilledButton.icon(
        key: const ValueKey('import-classify-merchants'),
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(Icons.category_outlined),
        label: const Text('Classify merchants'),
      ),
    ],
  );
}
