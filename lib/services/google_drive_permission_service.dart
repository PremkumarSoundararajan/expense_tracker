import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;

class GoogleDrivePermissionService {
  GoogleDrivePermissionService(
    GoogleSignIn googleSignIn, {
    Future<bool> Function(List<String>)? scopeChecker,
    Future<bool> Function(List<String>)? scopeRequester,
  }) : _scopeChecker = scopeChecker ?? googleSignIn.canAccessScopes,
       _scopeRequester = scopeRequester ?? googleSignIn.requestScopes;

  final Future<bool> Function(List<String>) _scopeChecker;
  final Future<bool> Function(List<String>) _scopeRequester;
  final Set<String> _confirmedScopes = {};

  static const _requiredWriteScopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  Future<bool> hasDriveWriteScope() async {
    return _hasScope(drive.DriveApi.driveFileScope);
  }

  Future<bool> ensureDriveWritePermission(BuildContext context) async {
    try {
      final missingScopes = <String>[];
      for (final scope in _requiredWriteScopes) {
        if (!await _hasScope(scope)) missingScopes.add(scope);
      }
      if (missingScopes.isEmpty) return true;

      if (!context.mounted) return false;

      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => _DrivePermissionDialog(
              requestPermission: () async {
                final granted = await _scopeRequester(missingScopes);
                if (granted) _confirmedScopes.addAll(missingScopes);
                return granted;
              },
            ),
          ) ??
          false;
    } catch (error) {
      if (!context.mounted) return false;
      _showPermissionError(context, error);
      return false;
    }
  }

  Future<bool> _hasScope(String scope) async {
    if (_confirmedScopes.contains(scope)) return true;
    try {
      return await _scopeChecker([scope]);
    } on UnimplementedError {
      // google_sign_in_android 6.x supports requesting scopes, but not checking
      // them. requestScopes() confirms existing grants without prompting.
      return false;
    }
  }

  void _showPermissionError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not check Google Drive permission: $error'),
      ),
    );
  }
}

class _DrivePermissionDialog extends StatefulWidget {
  const _DrivePermissionDialog({required this.requestPermission});

  final Future<bool> Function() requestPermission;

  @override
  State<_DrivePermissionDialog> createState() => _DrivePermissionDialogState();
}

class _DrivePermissionDialogState extends State<_DrivePermissionDialog> {
  bool _isRequesting = false;
  String? _errorMessage;

  Future<void> _grantPermission() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      final granted = await widget.requestPermission();
      if (!mounted) return;

      if (granted) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isRequesting = false;
          _errorMessage = 'Drive edit permission was not granted.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRequesting = false;
        _errorMessage = 'Could not request Drive permission: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Google Drive permission required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Google Drive access is required to find or create "Expense '
            'Tracker DB" and save expenses to it.',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isRequesting ? null : () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _isRequesting ? null : _grantPermission,
          child: _isRequesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Grant Permission'),
        ),
      ],
    );
  }
}
