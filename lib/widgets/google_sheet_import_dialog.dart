import 'package:flutter/material.dart';

import '../models/statement_source.dart';
import '../services/google_sheet_statement_service.dart';

class GoogleSheetImportDialog extends StatefulWidget {
  const GoogleSheetImportDialog({
    super.key,
    required this.loadWorkbook,
    required this.readWorksheet,
    required this.initialSource,
    required this.sourceName,
  });
  final String initialSource;
  final String sourceName;
  final Future<GoogleStatementWorkbook> Function(String) loadWorkbook;
  final Future<PreparedStatement> Function(
    GoogleStatementWorkbook,
    GoogleStatementTab,
  )
  readWorksheet;
  @override
  State<GoogleSheetImportDialog> createState() =>
      _GoogleSheetImportDialogState();
}

class _GoogleSheetImportDialogState extends State<GoogleSheetImportDialog> {
  GoogleStatementWorkbook? _workbook;
  GoogleStatementTab? _tab;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  bool get _active =>
      mounted && !_cancelled && (ModalRoute.of(context)?.isCurrent ?? false);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) _continue();
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_workbook == null) {
        final workbook = await widget.loadWorkbook(widget.initialSource);
        if (!_active) return;
        setState(() {
          _workbook = workbook;
          _tab = workbook.tabs.first;
        });
      } else {
        final statement = await widget.readWorksheet(_workbook!, _tab!);
        if (!mounted || !_active) return;
        Navigator.pop(context, statement);
      }
    } catch (error) {
      if (_active) {
        setState(
          () => _error = error is GoogleSheetImportException ? error.message : 'Could not load the sheet. Check your connection and try again.',
        );
      }
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import Google Sheets'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sourceName),
            if (_workbook != null) ...[
              const SizedBox(height: 16),
              Text(
                _workbook!.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(_workbook!.id),
                initialValue: _tab!.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Worksheet',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final tab in _workbook!.tabs)
                    DropdownMenuItem(
                      value: tab.id,
                      child: Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _tab = _workbook!.tabs.firstWhere(
                          (tab) => tab.id == id,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You will review transactions before anything is imported.',
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _workbook == null
                    ? 'Loading worksheets…'
                    : 'Reading transactions…',
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _cancelled = true;
          Navigator.pop(context);
        },
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _continue,
        child: Text(_workbook == null ? 'Load worksheets' : 'Continue'),
      ),
    ],
  );
}
