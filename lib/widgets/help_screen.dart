import 'package:flutter/material.dart';

class _HelpTopic {
  const _HelpTopic(this.title, this.text);
  final String title;
  final String text;
}

const _gettingStarted = [
  _HelpTopic(
    'Your Google Sheets ledger',
    'Grant the requested Google Drive and Sheets access so Pocket Ledger can create and update your ledger. It creates or reuses a spreadsheet named Expense Tracker DB in your Google Drive. Expenses and saved classification rules live in that spreadsheet. The app also keeps a local cache and pending changes for syncing.',
  ),
  _HelpTopic(
    'Add an expense manually',
    'Use Add New Expense on Home for everyday recording. Choose a category and Expense Type, enter the amount and details, then save. Need another category? Create it in Settings → Expense categories. Manual recording can help you stay aware of spending.',
  ),
  _HelpTopic(
    'Import first, classify later',
    'In Expenses, import a supported bank or credit-card statement in CSV or Excel format. Confirm the transactions and exclude any you do not want to import. Then use Classify expenses to open Financial Baseline in Insights. Organize merchants once instead of editing hundreds of transactions. You can still edit individual expenses for exceptions.',
  ),
  _HelpTopic(
    'Choose an Expense Type',
    'Regular: routine spending, such as groceries, transport or monthly bills.\n\nPlanned Occasional: expected but less frequent spending, such as annual insurance, scheduled taxes or a planned extra mortgage payment.\n\nUnexpected Occasional: an unplanned one-off expense, such as a surprise repair. A planned repair could instead be Planned Occasional. Choose based on the expense, not just its category.\n\nUnknown means the type has not been identified yet.',
  ),
  _HelpTopic(
    'Home: month, today and year',
    'This Month shows recorded actual spending. Expand it to set a budget, compare spending or browse past months. Tap a spending total to see categories. Today totals expenses dated today; This Year totals recorded expenses in the current calendar year. These are recorded expenses, not live bank balances.',
  ),
  _HelpTopic(
    'How the monthly budget comparison works',
    'Compared spending = Actual spending − Unexpected Occasional expenses. Regular, Planned Occasional and Unknown/NA amounts count against your budget.\n\nUnclassified amounts do not block the comparison. Tap the small unclassified amount to review that month’s Expense Types. This is separate from the Regular-only calculation used to suggest a budget.',
  ),
  _HelpTopic(
    'Find and edit recorded expenses',
    'Home shows the five most recent expenses. Tap one to edit it. View all opens Expenses, where recorded transactions are listed by date, newest first. Individual edits are useful for mixed-purpose merchants such as supermarkets and online marketplaces.',
  ),
  _HelpTopic(
    'Settings, currency and reminders',
    'Manage categories and mappings, choose a currency symbol, or switch dark mode in Settings. Changing the currency symbol does not convert recorded amounts.\n\nThe mobile app offers a daily reminder to record expenses. Web app access is also available from mobile Settings. Sign out disconnects the app session.',
  ),
  _HelpTopic(
    'Feedback and feature requests',
    'Use Submit feedback or request a feature in Settings. Type your message and continue to your email app, then send it to premkumar.soundararajan@gmail.com. Opening the email draft does not send it automatically.',
  ),
];

const _insights = [
  _HelpTopic(
    'Financial Baseline: start with the biggest merchants',
    'Expenses are grouped using normalized merchant names and ranked by total recorded spending. Choose Unclassified to organize what remains, or Classified to review previous choices. Counts show merchants; percentages show their share of spending.\n\nTop 15 and the percentage options help focus your effort. Classifying roughly 80% of spending is a useful starting point, not a requirement to finish every merchant. You can review the rest whenever you want.',
  ),
  _HelpTopic(
    'Category, Expense Type and Essentiality',
    'Category explains where money goes and powers expense breakdowns.\n\nExpense Type distinguishes Regular, Planned Occasional and Unexpected Occasional spending for budgets and trends.\n\nEssentiality supports savings planning: Essential covers needs and commitments within your current lifestyle; Potentially Flexible identifies spending you may choose to adjust.',
  ),
  _HelpTopic(
    'Merchant choices and transaction exceptions',
    'Save a merchant’s category, Expense Type and Essentiality to apply them to matching historical and future transactions, including later statement imports. Expand a merchant to view transactions and change individual exceptions. Explicit transaction choices take priority over the merchant choice. Filters help you revisit a category, Expense Type or Essentiality. Classified opens with Essentiality and Category charts. Tap a chart or Review classified merchants to edit the table; Back to charts returns to the overview. Coverage is shown separately for each dimension; the charts use all recorded eligible history, including transaction exceptions.',
  ),
  _HelpTopic(
    'Bulk exclude small merchants',
    'From Unclassified, open Bulk exclude small merchants, enter an amount and choose Exclude. The saved rule uses each normalized merchant’s total recorded spending across all time, not each transaction or just this month.\n\nUnclassified merchants below the limit receive NA choices and move to Excluded. Future imports keep applying the rule. At or above the limit, excluded merchants return to Unclassified for review. Existing classified merchants and individual exceptions are preserved.\n\nExcluded expenses are not deleted: they still count in actual spending and monthly budget comparisons. Review or change them under Excluded. A warning appears if your selection affects more than 25% of transactions.',
  ),
  _HelpTopic(
    'Spending trends',
    'Compare Actual or Regular spending in daily, monthly or yearly views. The current period is still in progress; historical averages use completed periods. These views help you spot changes in your recorded spending.',
  ),
  _HelpTopic(
    'Spending spots',
    'See your top five normalized merchants over the last six completed months, or the available completed history. Switch between Actual, Regular and Occasional spending. Totals and monthly averages help you identify your biggest spending spots. Financial Baseline uses all recorded history, so its ranking may differ.',
  ),
  _HelpTopic(
    'Savings insights and reduction plans',
    'See Essential, Potentially Flexible and unclassified spending, normalized to monthly amounts using completed history. Explore flexible spending by merchant or category and try percentage reductions. A what-if plan does not change your spending or move money. Review and activate targets when you want to track a plan.',
  ),
  _HelpTopic(
    'How is the suggested budget calculated?',
    'The suggestion uses Regular spending only, from up to six recent completed months, plus a 10% buffer. It needs at least two completed months of history; the current partial month is excluded.\n\nRecurring items use monthly averages over their active history. Other Regular spending uses averages that reduce the effect of spikes. Inactive recurring items can be excluded. Planned Occasional, Unexpected Occasional and Unknown/NA spending are not included in the suggestion.\n\nOpen Suggested budget to review the breakdown and use the amount if it suits you. Allow separately for planned occasional costs when choosing your final budget. The monthly comparison includes these costs, so it has a broader scope than the suggestion.',
  ),
  _HelpTopic(
    'Spending targets',
    'Review active merchant or category spending limits and edit your reduction plans. Progress and in-app notices help you see when spending approaches or crosses a target. Target edits apply from the displayed effective date. Targets are spending plans, not automatic transfers or guaranteed savings.',
  ),
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
                      children: [Text(topic.text)],
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
