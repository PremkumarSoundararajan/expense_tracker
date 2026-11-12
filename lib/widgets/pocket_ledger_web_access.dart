import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/merchant_classification_store.dart';
import '../services/pocket_ledger_web_access.dart';

bool shouldSuggestPocketLedgerDesktop({
  required int merchantsNeedingReview,
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb &&
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS) &&
    merchantsNeedingReview > 20;

const _pendingSyncNote =
    'Some merchant changes are saved on this device and waiting to sync. The web app may not show them yet.';

class MerchantDesktopSuggestion extends StatefulWidget {
  const MerchantDesktopSuggestion({
    super.key,
    required this.store,
    required this.merchantsNeedingReview,
    this.hasUnsavedChanges = false,
    this.launcher,
  });
  final MerchantClassificationStore store;
  final int merchantsNeedingReview;
  final bool hasUnsavedChanges;
  final PocketLedgerBrowserLauncher? launcher;
  @override
  State<MerchantDesktopSuggestion> createState() =>
      _MerchantDesktopSuggestionState();
}

class _MerchantDesktopSuggestionState extends State<MerchantDesktopSuggestion> {
  bool? _dismissed;
  @override
  void initState() {
    super.initState();
    _loadDismissal();
  }

  @override
  void didUpdateWidget(covariant MerchantDesktopSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      _dismissed = null;
      _loadDismissal();
    }
  }

  Future<void> _loadDismissal() async {
    final store = widget.store;
    try {
      final dismissed = await store.desktopSuggestionDismissed();
      if (mounted && identical(widget.store, store))
        setState(() => _dismissed = dismissed);
    } catch (_) {
      if (mounted && identical(widget.store, store))
        setState(() => _dismissed = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await widget.store.dismissDesktopSuggestion();
    } catch (_) {
      // Keep this visit dismissed even if local preference storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed != false ||
        !shouldSuggestPocketLedgerDesktop(
          merchantsNeedingReview: widget.merchantsNeedingReview,
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        ))
      return const SizedBox.shrink();
    return Container(
      key: const ValueKey('merchant-desktop-suggestion'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Organizing many merchants?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Reviewing merchants may be easier on a laptop or desktop.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.store.pending.isNotEmpty)
                  Text(
                    _pendingSyncNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                TextButton(
                  onPressed: () => openPocketLedgerWeb(
                    context,
                    store: widget.store,
                    hasUnsavedChanges: widget.hasUnsavedChanges,
                    launcher: widget.launcher,
                  ),
                  child: const Text('Open Pocket Ledger Web'),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('dismiss-desktop-suggestion'),
            tooltip: 'Dismiss desktop suggestion',
            onPressed: _dismiss,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class PocketLedgerWebSettingsTile extends StatelessWidget {
  const PocketLedgerWebSettingsTile({
    super.key,
    required this.store,
    this.launcher,
  });
  final MerchantClassificationStore store;
  final PocketLedgerBrowserLauncher? launcher;
  @override
  Widget build(BuildContext context) => kIsWeb
      ? const SizedBox.shrink()
      : ListTile(
          key: const ValueKey('pocket-ledger-web-settings'),
          leading: const Icon(Icons.desktop_windows_outlined),
          title: const Text('Pocket Ledger Web'),
          subtitle: Text(
            'Access Pocket Ledger from your laptop or desktop.${store.pending.isEmpty ? '' : '\n$_pendingSyncNote'}',
          ),
          onTap: () =>
              openPocketLedgerWeb(context, store: store, launcher: launcher),
        );
}
