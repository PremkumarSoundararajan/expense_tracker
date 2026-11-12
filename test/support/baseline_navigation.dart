import 'package:flutter_test/flutter_test.dart';

Future<void> openClassifiedTable(WidgetTester tester) async {
  final review = find.text('Review classified merchants');
  await tester.ensureVisible(review);
  await tester.pumpAndSettle();
  await tester.tap(review);
  await tester.pumpAndSettle();
}
