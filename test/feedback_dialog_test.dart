import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/feedback_dialog.dart';

void main() {
  testWidgets(
    'feedback requires a message and addresses the developer without sending automatically',
    (tester) async {
      Uri? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackDialog(
              send: (uri) async {
                sent = uri;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Submit via email'));
      await tester.pumpAndSettle();
      expect(sent, isNull);
      expect(
        find.text('Please enter your feedback or request.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Please add graphs & charts.',
      );
      await tester.tap(find.text('Submit via email'));
      await tester.pumpAndSettle();
      expect(sent!.scheme, 'mailto');
      expect(sent!.path, 'premkumar.soundararajan@gmail.com');
      expect(sent!.queryParameters['body'], 'Please add graphs & charts.');
      expect(sent!.queryParameters['subject'], 'Pocket Ledger: Feedback');
      expect(find.text('Copy message'), findsOneWidget);
    },
  );
}
