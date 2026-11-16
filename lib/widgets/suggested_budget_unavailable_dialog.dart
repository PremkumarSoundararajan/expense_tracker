import 'package:flutter/material.dart';

import '../services/suggested_budget_service.dart';

enum SuggestedBudgetNextStep { classify, manual }

class SuggestedBudgetUnavailableDialog extends StatelessWidget {
  const SuggestedBudgetUnavailableDialog({super.key, required this.assessment});

  final SuggestedBudgetAssessment assessment;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Suggested budget isn’t ready yet'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(assessment.explanation),
        if (assessment.unknownCount > 0) ...[
          const SizedBox(height: 12),
          Text(
            '${assessment.unknownCount} completed-month expenses have an Unknown Expense Type.',
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, SuggestedBudgetNextStep.classify),
            child: const Text('Classify expenses'),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, SuggestedBudgetNextStep.manual),
        child: const Text('Set budget manually'),
      ),
    ],
  );
}
