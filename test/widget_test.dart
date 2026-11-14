// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  testWidgets('iOS email hint is sent to native sign-in and cancellation allows retry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('pocket_ledger/google_account');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false; // User cancels Google's window.
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a different Google account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'review@example.com');
    await tester.tap(find.text('Continue to Google'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'signInWithEmail');
    expect(calls.single.arguments, {'email': 'review@example.com'});
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android does not expose the iOS email hint flow', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
    await tester.pumpAndSettle();
    expect(find.text('Use a different Google account'), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows the sign-in screen when there is no saved user', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
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

    await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
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
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restores the saved dark-mode preference', (tester) async {
    SharedPreferences.setMockInitialValues({'dark_mode_enabled': true});

    await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets(
    'failed credential restore returns to sign-in instead of a startup spinner',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_googleSignInChannel, (call) async {
            if (call.method == 'signInSilently') {
              throw PlatformException(code: 'sign_in_required');
            }
            return null;
          });
      await tester.pumpWidget(PocketLedgerApp(googleSignIn: GoogleSignIn()));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
