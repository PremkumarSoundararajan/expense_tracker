import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:pocket_ledger/services/google_drive_permission_service.dart';

void main() {
  testWidgets('uses Android scope request as the permission check fallback', (
    tester,
  ) async {
    final requestedScopes = <String>[];
    final service = GoogleDrivePermissionService(
      GoogleSignIn(),
      scopeChecker: (_) => throw UnimplementedError(),
      scopeRequester: (scopes) async {
        requestedScopes.addAll(scopes);
        return true;
      },
    );
    Future<bool>? permissionResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                permissionResult = service.ensureDriveWritePermission(context);
              },
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Grant Permission'), findsOneWidget);

    await tester.tap(find.text('Grant Permission'));
    await tester.pumpAndSettle();

    expect(await permissionResult, isTrue);
    expect(
      requestedScopes,
      containsAll([
        drive.DriveApi.driveFileScope,
        sheets.SheetsApi.spreadsheetsScope,
      ]),
    );
    expect(await service.hasDriveWriteScope(), isTrue);
  });
}
