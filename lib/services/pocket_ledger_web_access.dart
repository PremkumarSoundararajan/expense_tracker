import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'merchant_classification_store.dart';

/// Shared production destination. Override only for an intentional deployment.
const pocketLedgerWebUrl = String.fromEnvironment(
  'POCKET_LEDGER_WEB_URL',
  defaultValue: 'https://pocket-ledger-cdn.pages.dev/',
);

typedef PocketLedgerBrowserLauncher = Future<bool> Function(
  Uri uri,
  LaunchMode mode,
);

Future<bool> _launchBrowser(Uri uri, LaunchMode mode) =>
    launchUrl(uri, mode: mode);

Future<void> openPocketLedgerWeb(
  BuildContext context, {
  required MerchantClassificationStore store,
  bool hasUnsavedChanges = false,
  PocketLedgerBrowserLauncher? launcher,
}) async {
  if (hasUnsavedChanges || store.draft.isNotEmpty) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Open web app with unsaved changes?'),
        content: Text(
          'You have unsaved classification edits on this device. The web app may not reflect them yet. Stay to save first, or continue while keeping your local draft.'
          '${store.pending.isEmpty ? '' : '\n\nOther saved merchant changes are also waiting to sync.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay and save first'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open web app'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
  }
  try {
    final opened = await (launcher ?? _launchBrowser)(
      Uri.parse(pocketLedgerWebUrl),
      LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('Browser launch failed');
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the browser. Please try again, or visit $pocketLedgerWebUrl on your computer.',
          ),
        ),
      );
  }
}
