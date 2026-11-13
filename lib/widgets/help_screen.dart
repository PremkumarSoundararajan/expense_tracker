import 'package:flutter/material.dart';

class _HelpPoint {
  const _HelpPoint(this.label, this.text);
  final String label;
  final String text;
}

class _HelpTopic {
  const _HelpTopic(this.title, this.points);
  final String title;
  final List<_HelpPoint> points;
  String get text =>
      points.map((point) => '${point.label} ${point.text}').join(' ');
}

const _gettingStarted = [
  _HelpTopic('Your Google Sheets ledger', [
    _HelpPoint(
      'Connect',
      'Grant Google Drive and Sheets access to create and update your ledger.',
    ),
    _HelpPoint(
      'Your spreadsheet',
      'Pocket Ledger creates or reuses Expense Tracker DB in your Google Drive.',
    ),
    _HelpPoint(
      'What is saved',
      'Expenses, categories and merchant classification rules live in that spreadsheet.',
    ),
    _HelpPoint(
      'On this device',
      'A local cache keeps your history and pending changes for syncing.',
    ),
  ]),
  _HelpTopic('Add an expense manually', [
    _HelpPoint('Start', 'Open Add New Expense on Home for everyday recording.'),
    _HelpPoint(
      'Enter',
      'Choose a category and Expense Type, add the amount and details, then save.',
    ),
    _HelpPoint(
      'Need a category?',
      'Create it in Settings → Expense categories.',
    ),
    _HelpPoint(
      'Build awareness',
      'Manual recording can help you notice spending habits.',
    ),
  ]),
  _HelpTopic('Import first, classify later', [
    _HelpPoint(
      'Import',
      'In Expenses, tap Import Statements to choose a statement directly from your device or available cloud storage.',
    ),
    _HelpPoint(
      'Google Sheets',
      'On Android, select a sheet from Google Drive in the device picker. It is downloaded automatically for review. On computers, select a local Google Drive (.gsheet) shortcut, then choose the worksheet; your signed-in account needs access. CSV and Excel files can also be selected directly.',
    ),
    _HelpPoint(
      'Review',
      'Check and edit transactions or exclude rows before importing. Matching duplicates are skipped.',
    ),
    _HelpPoint(
      'Classify next',
      'Choose Classify expenses to open Financial Baseline in Insights.',
    ),
    _HelpPoint(
      'Save effort',
      'Organize a merchant once. Edit individual expenses only when you need an exception.',
    ),
  ]),
  _HelpTopic('Choose an Expense Type', [
    _HelpPoint(
      'Regular',
      'Routine spending, such as groceries, transport and monthly bills.',
    ),
    _HelpPoint(
      'Planned Occasional',
      'Expected but less frequent costs, such as annual insurance, scheduled taxes or a planned extra mortgage payment.',
    ),
    _HelpPoint(
      'Unexpected Occasional',
      'An unplanned one-off cost, such as a surprise repair. A planned repair could be Planned Occasional.',
    ),
    _HelpPoint('Unknown', 'The Expense Type has not been identified yet.'),
    _HelpPoint(
      'Your choice',
      'Choose based on the expense and its purpose, not just its category.',
    ),
  ]),
  _HelpTopic('Home: month, today and year', [
    _HelpPoint(
      'This Month',
      'See actual spending. Expand to set a budget, compare spending or browse past months.',
    ),
    _HelpPoint('Today', 'See expenses dated today.'),
    _HelpPoint(
      'This Year',
      'See recorded spending in the current calendar year.',
    ),
    _HelpPoint(
      'Explore',
      'Tap a spending total to view categories, then tap a category to see expenses.',
    ),
    _HelpPoint(
      'What totals mean',
      'These are recorded expenses, not live bank balances.',
    ),
  ]),
  _HelpTopic('How the monthly budget comparison works', [
    _HelpPoint(
      'Compared spending',
      'Actual spending − Unexpected Occasional expenses.',
    ),
    _HelpPoint(
      'Included',
      'Regular, Planned Occasional and Unknown/NA amounts count against your budget.',
    ),
    _HelpPoint(
      'Review unclassified',
      'Tap the unclassified amount to review that month’s Expense Types. It does not block the comparison.',
    ),
    _HelpPoint(
      'Suggested budget',
      'Its calculation uses Regular spending only, so its scope is different from the monthly comparison.',
    ),
  ]),
  _HelpTopic('Find and edit recorded expenses', [
    _HelpPoint(
      'Recent expenses',
      'Home shows your five most recent expenses. Tap one to edit it.',
    ),
    _HelpPoint(
      'View all',
      'Open Expenses to see recorded transactions, newest date first.',
    ),
    _HelpPoint(
      'Individual exceptions',
      'Use transaction edits for mixed-purpose merchants, such as supermarkets and online marketplaces.',
    ),
  ]),
  _HelpTopic('Settings, currency and reminders', [
    _HelpPoint('Categories', 'Manage expense categories and their mappings.'),
    _HelpPoint(
      'Currency',
      'Choose a symbol. Changing it does not convert recorded amounts.',
    ),
    _HelpPoint('Appearance', 'Switch between light and dark mode.'),
    _HelpPoint(
      'Daily reminder',
      'The mobile app can remind you to record expenses.',
    ),
    _HelpPoint(
      'Web access',
      'Open the web app from mobile Settings when you prefer a larger screen.',
    ),
    _HelpPoint('Sign out', 'Disconnect the app session from Settings.'),
  ]),
  _HelpTopic('Feedback and feature requests', [
    _HelpPoint(
      'Open',
      'Choose Submit feedback or request a feature in Settings.',
    ),
    _HelpPoint('Write', 'Enter your message and continue to your email app.'),
    _HelpPoint(
      'Send',
      'Press Send there to email premkumar.soundararajan@gmail.com. Opening the draft does not send it automatically.',
    ),
  ]),
];

const _insights = [
  _HelpTopic('Financial Baseline: start with the biggest merchants', [
    _HelpPoint(
      'Biggest first',
      'Transactions are grouped by normalized merchant name and ranked by total spending.',
    ),
    _HelpPoint('Unclassified', 'Organize merchants that still need choices.'),
    _HelpPoint(
      'Classified',
      'View spending charts, then open the merchant table to review your choices.',
    ),
    _HelpPoint(
      'Counts and percentages',
      'Counts show merchants. Percentages show their share of spending.',
    ),
    _HelpPoint(
      'Focus your effort',
      'Use Top 15 or a coverage percentage. Around 80% is a useful starting point; reviewing the rest is optional.',
    ),
  ]),
  _HelpTopic('Category, Expense Type and Essentiality', [
    _HelpPoint('Category → breakdowns', 'Explains where your money goes.'),
    _HelpPoint(
      'Expense Type → budgets',
      'Separates Regular, Planned Occasional and Unexpected Occasional spending for budgets and trends.',
    ),
    _HelpPoint(
      'Essential',
      'Needs and commitments within your current lifestyle.',
    ),
    _HelpPoint(
      'Potentially Flexible',
      'Spending you may choose to adjust when planning savings.',
    ),
  ]),
  _HelpTopic('Merchant choices and transaction exceptions', [
    _HelpPoint(
      'Classify once',
      'Save a merchant’s Category, Expense Type and Essentiality.',
    ),
    _HelpPoint(
      'Applies to',
      'Matching historical and future transactions, including later statement imports.',
    ),
    _HelpPoint(
      'Make an exception',
      'Expand the merchant and change an individual transaction. Explicit transaction choices take priority.',
    ),
    _HelpPoint(
      'Review later',
      'Use filters to revisit a Category, Expense Type or Essentiality.',
    ),
  ]),
  _HelpTopic('Review charts and classified merchants', [
    _HelpPoint(
      'Start with charts',
      'Classified opens with Essentiality and Category views.',
    ),
    _HelpPoint(
      'Open the table',
      'Tap a chart or Review classified merchants to edit your choices.',
    ),
    _HelpPoint(
      'Return',
      'Back to charts returns to the selected view without discarding unsaved edits.',
    ),
    _HelpPoint(
      'Coverage',
      'Each chart shows its own classification coverage, using total eligible history and transaction exceptions.',
    ),
  ]),
  _HelpTopic('Bulk exclude small merchants', [
    _HelpPoint(
      'Set a limit',
      'In Unclassified, open Bulk exclude small merchants, enter an amount and choose Exclude.',
    ),
    _HelpPoint(
      'What is compared',
      'Each merchant’s total recorded spending across all time, not a single transaction or month.',
    ),
    _HelpPoint(
      'Below the limit',
      'Unclassified merchants receive NA choices and move to Excluded. The rule also applies to future imports.',
    ),
    _HelpPoint(
      'At or above the limit',
      'Excluded merchants return to Unclassified for review.',
    ),
    _HelpPoint(
      'Spending still counts',
      'Excluded expenses remain in actual totals and monthly budget comparisons. Review them under Excluded.',
    ),
    _HelpPoint(
      'Safeguards',
      'Existing classified merchants and individual exceptions are preserved. A warning appears above 25% of transactions.',
    ),
  ]),
  _HelpTopic('Spending trends', [
    _HelpPoint('Choose spending', 'Switch between Actual and Regular.'),
    _HelpPoint('Choose a period', 'View daily, monthly or yearly spending.'),
    _HelpPoint(
      'Compare',
      'The current period is in progress. Historical averages use completed periods.',
    ),
  ]),
  _HelpTopic('Spending spots', [
    _HelpPoint(
      'Top five',
      'See your biggest normalized merchants over the last six completed months, or the completed history available.',
    ),
    _HelpPoint('Filter', 'Choose Actual, Regular or Occasional spending.'),
    _HelpPoint('Compare', 'Review each merchant’s total and monthly average.'),
    _HelpPoint(
      'Different rankings?',
      'Financial Baseline uses all recorded history, so its order may differ.',
    ),
  ]),
  _HelpTopic('Savings insights and reduction plans', [
    _HelpPoint(
      'Understand',
      'Compare Essential, Potentially Flexible and unclassified spending as monthly amounts from completed history.',
    ),
    _HelpPoint(
      'Explore',
      'Review flexible spending by merchant or category and try percentage reductions.',
    ),
    _HelpPoint('Plan', 'What-if changes do not move money or alter expenses.'),
    _HelpPoint(
      'Track',
      'Review and activate spending targets when you want to follow a plan.',
    ),
  ]),
  _HelpTopic('How is the suggested budget calculated?', [
    _HelpPoint(
      'History',
      'Needs at least two completed months; uses up to six recent completed months. The current partial month is excluded.',
    ),
    _HelpPoint('Included', 'Regular spending only, plus a 10% buffer.'),
    _HelpPoint(
      'Averages',
      'Recurring expenses use active-history averages. Other Regular spending is smoothed to reduce spikes; inactive recurring items can be excluded.',
    ),
    _HelpPoint(
      'Left out',
      'Planned Occasional, Unexpected Occasional and Unknown/NA expenses are excluded from the suggestion.',
    ),
    _HelpPoint(
      'Use it',
      'Open Suggested budget, review the breakdown and choose Use this budget if it suits you.',
    ),
    _HelpPoint(
      'Allow for planned costs',
      'The monthly comparison also includes Planned Occasional and Unknown/NA spending. Allow for those costs when setting your final budget.',
    ),
  ]),
  _HelpTopic('Spending targets', [
    _HelpPoint(
      'Review and edit',
      'Manage active merchant or category limits and reduction plans.',
    ),
    _HelpPoint(
      'Track progress',
      'In-app notices highlight spending approaching or crossing a target.',
    ),
    _HelpPoint('Effective date', 'Target edits apply from the displayed date.'),
    _HelpPoint(
      'Purpose',
      'Targets track a spending plan; they do not transfer money or guarantee savings.',
    ),
  ]),
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.insightsOnly = false});
  final bool insightsOnly;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final topics = widget.insightsOnly ? _insights : _gettingStarted;
    final visible = topics.where(
      (topic) => '${topic.title} ${topic.text}'.toLowerCase().contains(_query),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.insightsOnly ? 'Insights help' : 'Help & how it works',
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.insightsOnly
                      ? 'Understand your spending, one merchant at a time.'
                      : 'Record expenses → classify merchants → explore insights.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search help',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                if (!widget.insightsOnly)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Insights help'),
                      subtitle: const Text(
                        'Classification, savings, budgets and targets',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const HelpScreen(insightsOnly: true),
                        ),
                      ),
                    ),
                  ),
                for (final topic in visible)
                  Card(
                    child: ExpansionTile(
                      key: ValueKey(topic.title),
                      title: Text(topic.title),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      children: [
                        for (final point in topic.points)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    right: 12,
                                  ),
                                  child: ExcludeSemantics(
                                    child: Icon(
                                      Icons.circle,
                                      size: 6,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${point.label}: ',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        TextSpan(text: point.text),
                                      ],
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No matching topics. Try another word or open Insights help.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
