import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _retirementText =
    'Email scanning has been removed. Pocket Ledger no longer scans Gmail. Recorded expenses stay in Google Sheets; unimported email drafts are not retained.';

class EmailRetirementNotice extends StatelessWidget {
  const EmailRetirementNotice({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Privacy update'),
    content: const SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_retirementText),
          SizedBox(height: 12),
          Text(
            'Previously connected Gmail? You can also review and remove Pocket Ledger access in your Google Account. Removing Google access may require signing in again.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          try {
            final opened = await launchUrl(
              Uri.parse('https://myaccount.google.com/connections'),
              mode: LaunchMode.externalApplication,
            );
            if (!opened && context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Visit myaccount.google.com/connections to review access.',
                  ),
                ),
              );
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Visit myaccount.google.com/connections to review access.',
                  ),
                ),
              );
          }
        },
        child: const Text('Review Google access'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class EmailRetirementBanner extends StatefulWidget {
  const EmailRetirementBanner({super.key});
  @override
  State<EmailRetirementBanner> createState() => _EmailRetirementBannerState();
}

class _EmailRetirementBannerState extends State<EmailRetirementBanner> {
  bool _visible = false;
  static const _key = 'email_scan_retirement_notice_v1';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _visible = !(prefs.getBool(_key) ?? false));
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox.shrink()
      : Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Email scanning has been removed'),
            subtitle: const Text(
              'Your recorded expenses are unchanged. Tap for details.',
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const EmailRetirementNotice(),
            ),
            trailing: IconButton(
              tooltip: 'Dismiss privacy update',
              icon: const Icon(Icons.close),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_key, true);
                if (mounted) setState(() => _visible = false);
              },
            ),
          ),
        );
}
