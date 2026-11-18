import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openClassifiedTable(WidgetTester tester) async {
  final review = find.text('Review classified merchants');
  if (review.evaluate().isNotEmpty) {
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();
  }
  expect(
    find.byKey(const ValueKey('baseline-search-classified')),
    findsOneWidget,
  );
}
