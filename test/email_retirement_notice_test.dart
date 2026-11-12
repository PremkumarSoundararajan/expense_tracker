import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/email_retirement_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('privacy notice explains retirement and can be dismissed persistently', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EmailRetirementBanner())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email scanning has been removed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pocket Ledger no longer scans Gmail'), findsOneWidget);
    expect(find.text('Review Google access'), findsOneWidget);
    expect(find.text('Connect Gmail'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss privacy update'));
    await tester.pumpAndSettle();
    expect(find.text('Email scanning has been removed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EmailRetirementBanner())));
    await tester.pumpAndSettle();
    expect(find.text('Email scanning has been removed'), findsNothing);
  });
}
