import 'package:flutter/material.dart';

import 'app_linear_progress_indicator.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    super.key,
    required this.email,
    required this.delete,
    required this.signOut,
    this.pending = false,
  });

  final String email;
  final Future<void> Function(void Function(String)) delete;
  final Future<void> Function() signOut;
  final bool pending;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool _busy = false;
  bool _started = false;
  bool _done = false;
  String _progress = '';
  String? _error;

  Future<void> _delete() async {
    if (!widget.pending && !_started) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permanently delete your account?'),
          content: const Text(
            'This cannot be undone. Your Pocket Ledger database '
            'in Google Sheets will be permanently deleted, including expenses, '
            'categories, merchant classifications and spending targets. '
            'Your Google account and unrelated files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _started = true;
      _error = null;
    });
    try {
      await widget.delete((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) {
        setState(() {
          _done = true;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pending || _started;
    return PopScope(
      canPop: !pending || _done,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Delete account and app data'),
          automaticallyImplyLeading: !pending || _done,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                if (_done) ...[
                  const Icon(Icons.check_circle_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Deletion complete',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your Pocket Ledger database and active server records have been deleted. '
                    'This device’s app data was cleared, Google access was revoked, and you have been signed out.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                    child: const Text('Done'),
                  ),
                ] else ...[
                  Text(
                    widget.email,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!pending) ...[
                    const Text('Permanently removes:'),
                    const SizedBox(height: 12),
                    for (final item in [
                      'Your “Expense Tracker DB” spreadsheet and its expense history',
                      'Other ledger files not connected on this device must be deleted separately in Google Drive',
                      'Categories, merchant classifications, budgets and spending targets',
                      'Any remaining server records and previous email authorizations',
                      'This device’s saved app data and reminders',
                      'Pocket Ledger’s access to your Google account',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('• $item'),
                      ),
                    const Text(
                      'Keep a separate copy first if you need your records. '
                      'Your Google account, original statements and unrelated files stay unchanged.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'Use the latest app on your other devices and sign out there too. '
                    'Offline copies on those devices cannot be erased from here. '
                    'Provider backups may remain until their retention period expires.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  if (_busy) ...[
                    const AppLinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(_progress)),
                    const SizedBox(height: 8),
                    const Text(
                      'Keep this screen open. If interrupted, deletion can be resumed.',
                    ),
                  ] else ...[
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Deletion is not complete. Some data may already be deleted. '
                        'Retry to finish. If Google access expired, sign out and sign in again.',
                      ),
                      const SizedBox(height: 16),
                    ] else if (pending) ...[
                      const Text(
                        'Deletion was interrupted. Resume to finish before using Pocket Ledger.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _delete,
                      child: Text(
                        pending
                            ? 'Resume deletion'
                            : 'Delete account and app data',
                      ),
                    ),
                    if (pending)
                      TextButton(
                        onPressed: () async {
                          await widget.signOut();
                          if (context.mounted) {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          }
                        },
                        child: const Text(
                          'Sign out — finish deletion after signing in again',
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
