// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocket_ledger/main.dart';

const _googleSignInChannel = MethodChannel('plugins.flutter.io/google_sign_in');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleSignInChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleSignInChannel, null);
  });

  testWidgets('shows the sign-in screen when there is no saved user', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PocketLedgerApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows the tagline while restoring sign-in', (tester) async {
    final signInResponse = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _googleSignInChannel,
          (call) => signInResponse.future,
        );

    await tester.pumpWidget(const PocketLedgerApp());
    await tester.pump();

    final logo = tester.getRect(find.byKey(const ValueKey('loading-logo')));
    final appName = tester.getRect(find.text('Pocket Ledger'));
    final tagline = tester.getRect(
      find.text('Manual logging → Mindful spending'),
    );
    expect(appName.top, greaterThanOrEqualTo(logo.bottom));
    expect(appName.top - logo.bottom, lessThanOrEqualTo(6));
    expect(tagline.top, greaterThanOrEqualTo(appName.bottom));
    expect(
      tester
          .widget<Text>(find.text('Manual logging → Mindful spending'))
          .style
          ?.fontSize,
      14,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    signInResponse.complete(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restores the saved dark-mode preference', (tester) async {
    SharedPreferences.setMockInitialValues({'dark_mode_enabled': true});

    await tester.pumpWidget(const PocketLedgerApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
