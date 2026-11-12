import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/services/classified_spending_breakdown_service.dart';
import 'package:pocket_ledger/widgets/spending_breakdown.dart';
import 'package:pocket_ledger/widgets/spending_summary_widget.dart';

ClassifiedSpendingBreakdown snapshot({double essential = 600}) =>
    ClassifiedSpendingBreakdown(
      ClassifiedSpendingDimension({
        'Essential': essential,
        'Potentially Flexible': 200,
      }, 1000),
      ClassifiedSpendingDimension({
        for (var i = 1; i <= 8; i++) 'Custom category $i': i * 20,
      }, 1000),
    );
void main() {
  setUpAll(() async {
    if (Platform.environment.containsKey('POCKET_LEDGER_CAPTURE')) {
      final font = FontLoader('CaptureFont')
        ..addFont(
          File(r'C:\Windows\Fonts\segoeui.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await font.load();
    }
  });
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('breakdown charts, category details and updates at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(ClassifiedSpendingBreakdown data) => MaterialApp(
        theme: ThemeData(
          brightness: width == 390 ? Brightness.dark : Brightness.light,
          fontFamily: Platform.environment.containsKey('POCKET_LEDGER_CAPTURE')
              ? 'CaptureFont'
              : null,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SpendingBreakdown(data: data, currencySymbol: r'$'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(snapshot()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('essentiality-donut')), findsOneWidget);
      expect(
        find.text('Essentiality classified: 80.0% of spending'),
        findsOneWidget,
      );
      expect(find.textContaining('75.0%'), findsOneWidget);
      if (Platform.environment['POCKET_LEDGER_CAPTURE']
          case final String folder) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$folder/breakdown-$width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(app(snapshot(essential: 400)));
      await tester.pumpAndSettle();
      expect(
        find.text('Essentiality classified: 60.0% of spending'),
        findsOneWidget,
      );
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      expect(
        find.text('Categories classified: 72.0% of spending'),
        findsOneWidget,
      );
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Custom category 1'), findsNothing);
      final all = find.text('View all categories (8)');
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('All categories'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Custom category 1'),
        150,
        scrollable: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Custom category 1'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty dimension offers a friendly state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpendingBreakdown(
            data: ClassifiedSpendingBreakdown(
              ClassifiedSpendingDimension({}, 100),
              ClassifiedSpendingDimension({}, 100),
            ),
            currencySymbol: r'$',
          ),
        ),
      ),
    );
    expect(find.text('No classified spending to display yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('essentiality-donut')), findsNothing);
  });
  testWidgets(
    'Trends always opens without requiring the retired enable toggle',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'periodic_summaries_enabled': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpendingSummaryWidget(
                transactions: const [],
                currencySymbol: r'$',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(
        find.text('Turn on summaries to view your spending averages.'),
        findsNothing,
      );
      expect(find.text('Average frequency'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spending-series-selector')),
        findsOneWidget,
      );
    },
  );
}
