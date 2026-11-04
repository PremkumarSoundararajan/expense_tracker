import 'package:flutter/material.dart';

import '../services/worker_csv_sync_service.dart';

class WorkerSpreadsheetDialog extends StatefulWidget {
  const WorkerSpreadsheetDialog({
    super.key,
    required this.initialSpreadsheetId,
    required this.onCreateSpreadsheet,
  });

  final String? initialSpreadsheetId;
  final Future<String> Function() onCreateSpreadsheet;

  @override
  State<WorkerSpreadsheetDialog> createState() =>
      _WorkerSpreadsheetDialogState();
}

class _WorkerSpreadsheetDialogState extends State<WorkerSpreadsheetDialog> {
  late final TextEditingController _controller;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialSpreadsheetId ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createSpreadsheet() async {
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });
    try {
      final spreadsheetId = await widget.onCreateSpreadsheet();
      if (!mounted) return;
      setState(() => _controller.text = spreadsheetId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not create spreadsheet: $error');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _save() {
    final spreadsheetId = normalizeSpreadsheetId(_controller.text);
    if (spreadsheetId == null) {
      setState(
        () => _errorMessage = 'Enter a valid Google spreadsheet ID or link.',
      );
      return;
    }
    Navigator.of(context).pop(spreadsheetId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CSV sync spreadsheet'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose the Google Sheet that will receive your Pocket Ledger '
              'CSV data.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_isCreating,
              decoration: const InputDecoration(
                labelText: 'Spreadsheet ID or Google Sheets URL',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
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
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _isCreating ? null : _createSpreadsheet,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: const Text('Create sheet'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _save,
          child: const Text('Save target'),
        ),
      ],
    );
  }
}
