import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/spending_insights_service.dart';
import 'package:pocket_ledger/widgets/spending_summary_widget.dart';

void main() {
  group('SpendingInsightsService', () {
    final service = SpendingInsightsService();
    final now = DateTime(2025, 8, 15);

    test(
      'hides insight when fewer than two completed months are available',
      () {
        final insight = service.getSpendingInsight(
          history: [
            Transaction(
              date: DateTime(2025, 7, 1),
              amount: 25,
              category: 'Lifestyle / Misc',
            ),
          ],
          category: 'Lifestyle / Misc',
          currentSpend: 50,
          now: now,
        );

        expect(insight, isNull);
      },
    );

    test('reports category spending at least 20 percent above its average', () {
      final insight = service.getSpendingInsight(
        history: [
          Transaction(
            date: DateTime(2025, 6, 1),
            amount: 50,
            category: 'Food / Household',
          ),
          Transaction(
            date: DateTime(2025, 7, 1),
            amount: 50,
            category: 'Food / Household',
          ),
        ],
        category: 'Food / Household',
        currentSpend: 60,
        now: now,
      );

      expect(insight, contains('Food / Household jumped 20%'));
    });

    test('hides insight when there is no category baseline', () {
      final insight = service.getSpendingInsight(
        history: [
          Transaction(
            date: DateTime(2025, 6, 10),
            amount: 50,
            category: 'Food / Household',
          ),
          Transaction(
            date: DateTime(2025, 7, 10),
            amount: 50,
            category: 'Food / Household',
          ),
        ],
        category: 'Transport',
        currentSpend: 60,
        now: now,
      );

      expect(insight, isNull);
    });

    test('hides insight when category spend is below the spike threshold', () {
      final insight = service.getSpendingInsight(
        history: [
          Transaction(
            date: DateTime(2025, 6, 1),
            amount: 50,
            category: 'Food / Household',
          ),
          Transaction(
            date: DateTime(2025, 7, 1),
            amount: 50,
            category: 'Food / Household',
          ),
        ],
        category: 'Food / Household',
        currentSpend: 59,
        now: now,
      );

      expect(insight, isNull);
    });
  });

  group('SpendingAverageData', () {
    test('compares today with the average of completed history days', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 3, 1),
            amount: 60,
            category: 'Food / Household',
          ),
          Transaction(
            date: DateTime(2025, 3, 2),
            amount: 40,
            category: 'Transport',
          ),
        ],
        frequency: SummaryFrequency.daily,
        now: DateTime(2025, 3, 2, 12),
      );

      expect(average.currentSpend, 40);
      expect(average.average, 60);
      expect(average.periodCount, 1);
      expect(average.averageLabel, 'Daily average');
      expect(average.currentLabel, 'Today');
    });

    test('compares month to date with completed-month average', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 1, 1),
            amount: 100,
            category: 'Food / Household',
          ),
          Transaction(
            date: DateTime(2025, 2, 15),
            amount: 200,
            category: 'Transport',
          ),
          Transaction(
            date: DateTime(2025, 3, 10),
            amount: 900,
            category: 'Lifestyle / Misc',
          ),
        ],
        frequency: SummaryFrequency.monthly,
        now: DateTime(2025, 3, 15),
      );

      expect(average.average, 150);
      expect(average.currentSpend, 900);
      expect(average.periodCount, 2);
      expect(average.averageLabel, 'Monthly average');
      expect(average.currentLabel, 'Month to date');
    });

    test('keeps month-to-date spend when there are no completed months', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 3, 10),
            amount: 72,
            category: 'Food / Household',
          ),
        ],
        frequency: SummaryFrequency.monthly,
        now: DateTime(2025, 3, 15),
      );

      expect(average.currentSpend, 72);
      expect(average.average, 0);
      expect(average.averageLabel, 'No completed months yet');
      expect(average.currentLabel, 'Month to date');
    });

    test('compares year to date with completed-year average', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2023, 1, 1),
            amount: 1200,
            category: 'Housing / Bills',
          ),
          Transaction(
            date: DateTime(2024, 7, 1),
            amount: 2400,
            category: 'Housing / Bills',
          ),
          Transaction(
            date: DateTime(2025, 6, 1),
            amount: 8000,
            category: 'Housing / Bills',
          ),
        ],
        frequency: SummaryFrequency.yearly,
        now: DateTime(2025, 9, 1),
      );

      expect(average.average, 1800);
      expect(average.currentSpend, 8000);
      expect(average.periodCount, 2);
      expect(average.averageLabel, 'Yearly average');
      expect(average.currentLabel, 'Year to date');
    });

    test('keeps year-to-date spend when there are no completed years', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 6, 1),
            amount: 315,
            category: 'Housing / Bills',
          ),
        ],
        frequency: SummaryFrequency.yearly,
        now: DateTime(2025, 9, 1),
      );

      expect(average.currentSpend, 315);
      expect(average.average, 0);
      expect(average.averageLabel, 'No completed years yet');
      expect(average.currentLabel, 'Year to date');
    });

    test('does not count the current incomplete day in its own average', () {
      final average = SpendingAverageData.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 3, 2, 8),
            amount: 60,
            category: 'Food / Household',
          ),
        ],
        frequency: SummaryFrequency.daily,
        now: DateTime(2025, 3, 2, 12),
      );

      expect(average.currentSpend, 60);
      expect(average.averageLabel, 'No completed days yet');
      expect(average.periodCount, 0);
    });
  });
}
