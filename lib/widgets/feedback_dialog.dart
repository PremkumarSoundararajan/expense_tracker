import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key, this.send});
  final Future<bool> Function(Uri)? send;
  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _message = TextEditingController();
  String _kind = 'Feedback';
  String? _error;
  bool _sending = false;
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Please enter your feedback or request.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final uri = Uri(
      scheme: 'mailto',
      path: 'premkumar.soundararajan@gmail.com',
      query:
          'subject=${Uri.encodeComponent('Pocket Ledger: $_kind')}&body=${Uri.encodeComponent(message)}',
    );
    try {
      final opened = await (widget.send?.call(uri) ?? launchUrl(uri));
      if (!mounted) return;
      if (opened) {
        Navigator.pop(context);
      } else {
        setState(
          () => _error = 'Could not open your email app. Copy the message and email premkumar.soundararajan@gmail.com.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not open your email app. Copy the message and email premkumar.soundararajan@gmail.com.',
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Feedback or feature request'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              items: const [
                DropdownMenuItem(value: 'Feedback', child: Text('Feedback')),
                DropdownMenuItem(
                  value: 'Feature request',
                  child: Text('Feature request'),
                ),
              ],
              onChanged: _sending
                  ? null
                  : (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              enabled: !_sending,
              decoration: const InputDecoration(
                labelText: 'Your message',
                border: OutlineInputBorder(),
              ),
            ),
            const Text('Opens your email app. Press Send there to submit.'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (_error != null)
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _message.text));
          },
          child: const Text('Copy message'),
        ),
      TextButton(
        onPressed: _sending ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _sending ? null : _submit,
        child: const Text('Submit via email'),
      ),
    ],
  );
}
