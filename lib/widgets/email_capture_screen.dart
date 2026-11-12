import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/email_capture_service.dart';
import '../utils/currency_format.dart';
import '../models/expense_category.dart';
import '../models/transaction.dart';

class EmailCaptureScreen extends StatefulWidget {
  const EmailCaptureScreen({
    super.key,
    required this.service,
    required this.reminderTime,
    required this.changeReminderTime,
    required this.onReview,
    required this.reminderFrequency,
    required this.changeReminderFrequency,
    this.settingsMode = false,
    this.openSettings,
    this.initialCurrency = 'USD',
    this.openAuthorization,
    this.categories = const [],
    this.prepareCandidate,
  });
  final EmailCaptureService service;
  final TimeOfDay Function() reminderTime;
  final Future<void> Function() changeReminderTime;
  final String Function() reminderFrequency;
  final Future<void> Function(String frequency) changeReminderFrequency;
  final bool settingsMode;
  final Future<void> Function()? openSettings;
  final Future<String> Function(
    List<EmailExpenseCandidate> candidates,
    String currency,
  )
  onReview;
  final String initialCurrency;
  final Future<bool> Function(Uri uri)? openAuthorization;
  final List<ExpenseCategory> categories;
  final EmailExpenseCandidate Function(EmailExpenseCandidate)? prepareCandidate;
  @override
  State<EmailCaptureScreen> createState() => _EmailCaptureScreenState();
}

class _EmailCaptureScreenState extends State<EmailCaptureScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _accounts = [];
  List<EmailExpenseCandidate> _items = [];
  List<EmailExpenseCandidate> _reviews = [];
  int _readyTotal = 0, _reviewTotal = 0;
  int _filteredBankDuplicates = 0;
  bool _showNeedsReview = false;
  final _selected = <String>{};
  final _expandedItems = <String>{};
  final _edits = <String, EmailExpenseCandidate>{};
  bool _busy = false;
  String? _error, _message;
  String _scanStatus = 'Ready to scan';
  String? _pauseReason;
  int _checkedEmails = 0;
  Map<String, dynamic>? _job;
  bool _watchingJob = false, _isForeground = true, _pausing = false;
  late final String _currency = widget.initialCurrency;
  bool _stopScan = false, _scanning = false;
  String _range = '7';
  final _days = TextEditingController(text: '7');
  String _errorMessage(Object error) =>
      error is StateError ? error.message.toString() : error.toString();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _stopScan = true;
    _days.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.service.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (!_isForeground) _stopScan = true; // Stop polling, not the server job.
    if (_isForeground && !_busy) _load();
  }

  Future<void> _load({bool clearError = true, bool autoPoll = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await widget.service.status();
      if (!mounted) return;
      setState(() {
        _accounts = (state['accounts'] as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _items = (state['items'] as List)
            .map(
              (x) => EmailExpenseCandidate.fromJson(
                Map<String, dynamic>.from(x as Map),
              ),
            )
            .map((item) => widget.prepareCandidate?.call(item) ?? item)
            .toList();
        _reviews = (state['needsReview'] as List? ?? [])
            .map(
              (x) => EmailExpenseCandidate.fromJson(
                Map<String, dynamic>.from(x as Map),
              ),
            )
            .map((item) => widget.prepareCandidate?.call(item) ?? item)
            .toList();
        _readyTotal = (state['pendingTotal'] as num?)?.toInt() ?? _items.length;
        _reviewTotal =
            (state['needsReviewTotal'] as num?)?.toInt() ?? _reviews.length;
        _filteredBankDuplicates =
            (state['filteredBankDuplicates'] as num?)?.toInt() ?? 0;
        if (!_scanning) {
          if (_accounts.any((a) => a['scan_start'] != null)) {
            _scanStatus = 'Paused';
          } else if (_scanStatus != 'Paused' &&
              _accounts.any((a) => (a['last_scan'] as num? ?? 0) > 0)) {
            _scanStatus = 'Complete';
          }
        }
        for (final account in _accounts) {
          if (account['job'] is Map)
            _applyJob(Map<String, dynamic>.from(account['job'] as Map));
        }
        if (_items.isEmpty && _reviews.isNotEmpty) _showNeedsReview = true;
        final all = [..._items, ..._reviews];
        _expandedItems.removeWhere((id) => !all.any((x) => x.id == id));
        _selected.removeWhere((id) => !all.any((x) => x.id == id));
        _edits.removeWhere(
          (id, _) => _items.any((x) => x.id == id && x.reviewBlocked),
        );
        _edits.removeWhere(
          (id, edited) =>
              all.any((x) => x.id == id && x.needsReview != edited.needsReview),
        );
        if (_range == 'last' &&
            !_accounts.any(
              (a) =>
                  (a['last_scan'] as num? ?? 0) >
                  DateTime.now()
                      .subtract(const Duration(days: 30))
                      .millisecondsSinceEpoch,
            ))
          _range = '7';
        if (clearError) _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        autoPoll &&
        !widget.settingsMode &&
        _isForeground &&
        !_watchingJob) {
      for (final account in _accounts) {
        if (account['job'] is Map && account['job']['status'] == 'running') {
          unawaited(
            _watchJob(
              account,
              Map<String, dynamic>.from(account['job'] as Map),
            ),
          );
          break;
        }
      }
    }
  }

  Future<void> _action(Future<void> Function() run) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await run();
    } catch (e) {
      if (mounted) setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    await _action(() async {
      final result = await widget.service.request(
        'connect',
        data: {'currency': _currency},
      );
      final url = Uri.parse(result['url'] as String);
      if (url.scheme != 'https' || url.host != 'accounts.google.com')
        throw StateError('Unexpected authorization destination.');
      if (!await (widget.openAuthorization?.call(url) ??
          launchUrl(url, mode: LaunchMode.externalApplication)))
        throw StateError('Could not open Gmail authorization in your browser.');
      if (mounted)
        setState(
          () => _message = 'After granting access, return here and refresh. Gmail access is read-only.',
        );
    });
  }

  void _applyJob(Map<String, dynamic> job) {
    _job = job;
    _checkedEmails = (job['processed'] as num? ?? 0).toInt();
    _scanStatus = switch (job['status']) {
      'running' =>
        (job['retryAt'] as num? ?? 0) > DateTime.now().millisecondsSinceEpoch
            ? 'Waiting for Gmail'
            : 'Scanning…',
      'complete' => 'Complete',
      'failed' => 'Needs attention',
      'paused' => 'Paused',
      _ => 'Ready to scan',
    };
    _pauseReason = job['error'] as String?;
  }

  Future<void> _scan(
    Map<String, dynamic> account, {
    bool resume = false,
  }) async {
    final days = int.tryParse(_days.text.trim());
    if (!resume &&
        _range != 'last' &&
        (days == null || days < 1 || days > 30)) {
      setState(
        () => _error =
            'Choose 1–30 days. Use bank statements for longer periods.',
      );
      return;
    }
    Map<String, dynamic>? job;
    await _action(() async {
      final result = await widget.service.request(
        'scan/start',
        data: {
          'accountId': account['id'],
          'currency': _currency,
          'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
          if (resume)
            'resume': true
          else if (_range == 'last')
            'sinceLast': true
          else
            'days': days,
        },
      );
      job = Map<String, dynamic>.from(result['job'] as Map);
      if (!mounted) return;
      setState(() {
        if (result['reset'] == true) {
          _items.clear();
          _reviews.clear();
          _edits.clear();
          _selected.clear();
          _expandedItems.clear();
          _readyTotal = 0;
          _reviewTotal = 0;
          _filteredBankDuplicates = 0;
        }
        _applyJob(job!);
        account['job'] = job;
        account['scan_from'] = job!['from'];
        account['scan_start'] = job!['status'] == 'running'
            ? job!['through']
            : null;
      });
    });
    if (mounted && job != null)
      await _watchJob(account, job!);
    else if (mounted)
      await _load();
  }

  Future<void> _watchJob(
    Map<String, dynamic> account,
    Map<String, dynamic> initial,
  ) async {
    if (_watchingJob) return;
    _watchingJob = true;
    _stopScan = false;
    var job = initial;
    setState(() {
      _busy = true;
      _scanning = job['status'] == 'running';
      _applyJob(job);
    });
    try {
      while (mounted &&
          !_stopScan &&
          _isForeground &&
          job['status'] == 'running') {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!mounted || _stopScan || !_isForeground) break;
        final result = await widget.service.request(
          'scan/progress',
          data: {'accountId': account['id']},
        );
        if (!mounted) return;
        if (result['job'] is! Map) break;
        job = Map<String, dynamic>.from(result['job'] as Map);
        setState(() => _applyJob(job));
      }
    } catch (error) {
      if (mounted)
        setState(
          () => _error = 'Could not refresh progress. The scan continues in the background. Pull to refresh.',
        );
    } finally {
      _watchingJob = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = false;
          _applyJob(job);
        });
        if (_isForeground && !_pausing)
          await _load(clearError: false, autoPoll: false);
      }
    }
  }

  Future<void> _pauseJob() async {
    if (_pausing || _accounts.isEmpty) return;
    _pausing = true;
    _stopScan = true;
    try {
      final result = await widget.service.request(
        'scan/pause',
        data: {'accountId': _accounts.first['id']},
      );
      if (mounted && result['job'] is Map)
        setState(
          () => _applyJob(Map<String, dynamic>.from(result['job'] as Map)),
        );
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      _pausing = false;
      if (mounted) {
        setState(() => _busy = false);
        await _load(clearError: false, autoPoll: false);
      }
    }
  }

  Future<void> _disconnect(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Gmail?'),
        content: Text(
          'Stop scanning ${account['email']} and delete its queued email proposals. Expenses already approved in Sheets remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _action(() async {
      final result = await widget.service.request(
        'disconnect',
        data: {'accountId': account['id']},
      );
      if (mounted)
        setState(
          () => _message = result['revoked'] == true ? 'Mailbox disconnected.' : 'Mailbox disconnected. You can also revoke access in your Google account.',
        );
    });
    await _load(clearError: false);
  }

  Future<void> _edit(EmailExpenseCandidate item) async {
    final merchant = TextEditingController(text: item.merchant),
        amount = TextEditingController(
          text: item.amountMissing ? '' : item.amount.toStringAsFixed(2),
        ),
        date = TextEditingController(text: item.date);
    var currency = item.currency;
    var confirmed = item.manualReviewConfirmed;
    String? error;
    final edited = await showDialog<EmailExpenseCandidate>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          scrollable: true,
          title: const Text('Verify email expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.needsReview) Text(emailReviewReason(item.reviewReason)),
              if (item.amountIsSuggestion)
                const Text(
                  'This amount was read from the email but is not a confirmed expense. Verify it against the original email.',
                ),
              TextField(
                controller: merchant,
                decoration: const InputDecoration(labelText: 'Merchant'),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              TextField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: 'Payment date (YYYY-MM-DD)',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: emailCurrencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => currency = v!,
              ),
              if (item.needsReview)
                CheckboxListTile(
                  value: confirmed,
                  onChanged: (value) =>
                      setDialog(() => confirmed = value ?? false),
                  title: const Text(
                    'I checked the original email. This is a completed expense, not an unpaid bill, refund, hold or transfer.',
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()),
                    parsed = DateTime.tryParse(date.text.trim());
                if (merchant.text.trim().isEmpty ||
                    value == null ||
                    !value.isFinite ||
                    value <= 0 ||
                    parsed == null ||
                    !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                        .hasMatch(date.text.trim()) ||
                    !parsed.toIso8601String().startsWith(date.text.trim()) ||
                    (item.needsReview && !confirmed)) {
                  setDialog(
                    () => error = 'Verify merchant, positive amount, payment date, and confirm that the payment completed.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  item.edited(
                    merchant: merchant.text.trim(),
                    amount: value,
                    date: date.text.trim(),
                    currency: currency,
                    manualReviewConfirmed: item.needsReview && confirmed,
                  ),
                );
              },
              child: const Text('Keep changes'),
            ),
          ],
        ),
      ),
    );
    // Dialog fields may still be animating out; dispose after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      merchant.dispose();
      amount.dispose();
      date.dispose();
    });
    if (edited != null && mounted)
      setState(() {
        _edits[item.id] = widget.prepareCandidate?.call(edited) ?? edited;
        if (edited.currency != _currency) _selected.remove(item.id);
      });
  }

  Future<void> _showEmailEvidence(
    EmailExpenseCandidate item,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Email evidence'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item.subject}\n${item.sender}\n${item.excerpt}'),
              if (item.needsReview)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    item.manualReviewConfirmed
                        ? 'Manually reviewed · ${item.reviewReason}'
                        : 'Needs review · ${item.reviewReason}\n${emailReviewReason(item.reviewReason)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              if (item.dateNeedsReview ||
                  item.merchantNeedsReview ||
                  item.currencyNeedsReview)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${item.dateSource} · Verify merchant, payment date/timezone and currency before importing.',
                  ),
                ),
              if (item.currencyNeedsReview)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Currency assumed from mailbox settings; verify before importing.',
                  ),
                ),
              if (item.amountWarning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(item.amountWarning),
                ),
              if (item.needsReview && item.amountCandidates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Amounts found in email (unconfirmed):'),
                      for (final candidate in item.amountCandidates)
                        Text(
                          '${candidate['label']}: ${candidate['currency'] ?? ''} ${candidate['amount'] is num ? (candidate['amount'] as num).toStringAsFixed(2) : candidate['amountText'] ?? 'Unreadable amount'}',
                        ),
                    ],
                  ),
                ),
              if (item.reviewBlocked)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Do not use this draft amount. The receipt format could not be safely re-read. Exclude this draft and add the expense manually after checking the email.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _classificationFields(EmailExpenseCandidate item) {
    final categories = widget.categories
        .where((c) => c.active && !c.archived)
        .toList();
    final byName = categories.where((c) => c.name == item.category).toList();
    final selected = categories.any((c) => c.id == item.categoryId)
        ? item.categoryId!
        : byName.length == 1
        ? byName.single.id
        : item.category == 'Uncategorized'
        ? '__unknown'
        : '__current';
    Widget dropdown(
      String field,
      String value,
      Map<String, String> choices,
      ValueChanged<String> changed,
    ) => DropdownButtonFormField<String>(
      key: ValueKey('email-${item.id}-$field-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: field, isDense: true),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) {
              if (value != null) changed(value);
            },
    );
    void save(EmailExpenseCandidate value) =>
        setState(() => _edits[item.id] = value);
    final fields = [
      dropdown(
        'Category',
        selected,
        {
          '__unknown': 'Uncategorized',
          if (selected == '__current') '__current': item.category,
          for (final c in categories) c.id: c.name,
        },
        (value) {
          if (value == '__current') return;
          final category = value == '__unknown'
              ? null
              : categories.firstWhere((c) => c.id == value);
          save(
            item.classified(
              category: category?.name ?? 'Uncategorized',
              categoryId: category?.id,
            ),
          );
        },
      ),
      dropdown('Essentiality', item.essentiality, {
        for (final s in ['Essential', 'Potentially Flexible', 'Unclassified'])
          s: s,
      }, (value) => save(item.classified(essentiality: value))),
      dropdown('Expense Type', item.expenseType, {
        for (final t in ExpenseType.values) t.sheetValue: t.sheetValue,
      }, (value) => save(item.classified(expenseType: value))),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 580
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final field in fields) SizedBox(width: width, child: field),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = [
      ..._items,
      ..._reviews,
    ].map((x) => _edits[x.id] ?? x).toList();
    final items = allItems
        .where((x) => x.needsReview == _showNeedsReview)
        .toList();
    final totals = <String, double>{};
    for (final item in items) {
      if (!item.needsReview || item.manualReviewConfirmed)
        totals[item.currency] = (totals[item.currency] ?? 0) + item.amount;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.settingsMode
              ? 'Email & scan reminders'
              : 'Scan email expenses',
        ),
        actions: [
          if (!widget.settingsMode)
            IconButton(
              tooltip: 'How scanning works',
              icon: const Icon(Icons.help_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Email scans'),
                  content: const Text(
                    'Start scan uses the selected dates. Starting a new scan clears unimported results and replaces paused progress. Expenses already added to Sheets stay.\n\nResume scan continues from the saved position and dates.\n\nScans continue on the server after you leave. Return here to see progress or results. Pause scan stops the job until you resume.\n\nOnly reviewed and approved expenses are added to Sheets. Text receipts are supported; PDF-only receipts may be skipped. Change the mailbox in Settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh email inbox',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Review receipts before adding them to Sheets.'),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  key: const ValueKey('email-capture-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_message != null) Text(_message!),
            const SizedBox(height: 12),
            Text('Gmail only · Currency: $_currency (from Settings)'),
            const Text('For older expenses, import a bank statement.'),
            if (widget.settingsMode) ...[
              const SizedBox(height: 12),
              const Text(
                'Mailbox changes are made here. Email is accessed only when you press Scan in Expenses.',
              ),
              if (_accounts.isEmpty)
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.add),
                  label: const Text('Connect Gmail'),
                ),
              for (final account in _accounts)
                ListTile(
                  title: Text(account['email'] as String),
                  subtitle: const Text(
                    'Disconnect this mailbox before choosing another. A new connection starts with no last scan.',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _disconnect(account),
                    child: const Text('Disconnect'),
                  ),
                ),
              const Divider(),
              if (kIsWeb)
                const Text(
                  'Set hourly or daily notifications in the Android or iOS app. You can start scans here on the web.',
                ),
              if (!kIsWeb) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'email-reminder-${widget.reminderFrequency()}-$_busy',
                  ),
                  initialValue: widget.reminderFrequency(),
                  decoration: const InputDecoration(
                    labelText: 'Remind me to scan emails',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'off', child: Text('Off')),
                    DropdownMenuItem(
                      value: 'hourly',
                      child: Text('Once an hour'),
                    ),
                    DropdownMenuItem(value: 'daily', child: Text('Once a day')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) async {
                          await _action(
                            () => widget.changeReminderFrequency(value!),
                          );
                          if (mounted) setState(() {});
                        },
                ),
                if (widget.reminderFrequency() == 'daily')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _action(widget.changeReminderTime);
                            if (mounted) setState(() {});
                          },
                    child: Text(
                      'Daily reminder: ${widget.reminderTime().format(context)}',
                    ),
                  ),
                const Text(
                  'Notifications remind you to scan; they never read email. Delivery time may vary with phone settings.',
                ),
              ],
            ] else ...[
              if (_accounts.isEmpty) ...[
                const Text('Connect a Gmail mailbox in Settings first.'),
                if (widget.openSettings != null)
                  TextButton(
                    onPressed: widget.openSettings,
                    child: const Text('Go to Settings'),
                  ),
              ],
              if (_accounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _range,
                  decoration: const InputDecoration(
                    labelText: 'New scan range',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '7',
                      child: Text('Previous days (up to 30)'),
                    ),
                    if (_accounts.any(
                      (a) =>
                          (a['last_scan'] as num? ?? 0) >
                          DateTime.now()
                              .subtract(const Duration(days: 30))
                              .millisecondsSinceEpoch,
                    ))
                      const DropdownMenuItem(
                        value: 'last',
                        child: Text('Since the last completed scan'),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _range = value!),
                ),
                if (_range != 'last')
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in [1, 7, 30])
                        ChoiceChip(
                          label: Text(
                            option == 1
                                ? 'Last 24 hours'
                                : option == 7
                                ? '7 days · Recommended'
                                : '30 days',
                          ),
                          selected: _days.text == '$option',
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _days.text = '$option'),
                        ),
                    ],
                  ),
                if (_range != 'last')
                  TextField(
                    controller: _days,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'How many days back?',
                      helperText: '7 days recommended · Maximum 30 days',
                    ),
                  ),
                for (final account in _accounts)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _scanStatus,
                            key: const ValueKey('email-scan-status'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (!_scanning && _scanStatus == 'Complete')
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Scan finished. Results are ready.',
                                  ),
                                ),
                              ],
                            ),
                          if (!_scanning && _scanStatus == 'Paused')
                            Text(
                              _pauseReason ??
                                  'Unfinished scan · Resume to continue',
                            ),
                          if (_scanStatus == 'Needs attention' &&
                              _pauseReason != null)
                            Text(
                              _pauseReason!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          Text(
                            account['email'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_scanStatus == 'Scanning…')
                            const Text('Continues in the background.'),
                          if (_scanStatus == 'Scanning…')
                            Text('Checked: $_checkedEmails emails'),
                          if (account['scan_start'] != null &&
                              account['scan_from'] is num)
                            Text(
                              'Saved range: ${DateTime.fromMillisecondsSinceEpoch((account['scan_from'] as num).toInt()).toLocal().toIso8601String().substring(0, 10)} to ${DateTime.fromMillisecondsSinceEpoch((account['scan_start'] as num).toInt()).toLocal().toIso8601String().substring(0, 10)}',
                            ),
                          if (account['scan_start'] == null &&
                              (account['last_scan'] as num? ?? 0) > 0)
                            Text(
                              'Last scan: ${DateTime.fromMillisecondsSinceEpoch((account['last_scan'] as num).toInt()).toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
                            ),
                          if (account['scan_start'] == null &&
                              account['scan_from'] is num &&
                              (account['last_scan'] as num? ?? 0) > 0)
                            Text(
                              'Last scan range: ${DateTime.fromMillisecondsSinceEpoch((account['scan_from'] as num).toInt()).toLocal().toIso8601String().substring(0, 10)} to ${DateTime.fromMillisecondsSinceEpoch((account['last_scan'] as num).toInt()).toLocal().toIso8601String().substring(0, 10)}',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (account['scan_start'] != null ||
                                  account['job']?['status'] == 'paused' ||
                                  account['job']?['status'] == 'failed') ...[
                                FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _scan(account, resume: true),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Resume scan'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _scan(account),
                                  child: const Text('Start new scan'),
                                ),
                              ] else
                                FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _scan(account),
                                  icon: const Icon(Icons.search),
                                  label: const Text('Start scan'),
                                ),
                            ],
                          ),
                          if (account['scan_start'] != null)
                            const Text(
                              'Resume continues saved dates. New scan clears old results.',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_scanning)
                  TextButton(
                    onPressed: _pausing ? null : _pauseJob,
                    child: const Text('Pause scan'),
                  ),
              ],
            ],
            if (!widget.settingsMode) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  ChoiceChip(
                    label: Text('Ready to import ($_readyTotal)'),
                    selected: !_showNeedsReview,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _showNeedsReview = false;
                            _selected.clear();
                          }),
                  ),
                  ChoiceChip(
                    label: Text('Needs review ($_reviewTotal)'),
                    selected: _showNeedsReview,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _showNeedsReview = true;
                            _selected.clear();
                          }),
                  ),
                ],
              ),
              if (_showNeedsReview)
                const Text('Check these payments before importing.'),
              if (_filteredBankDuplicates > 0)
                Text(
                  '$_filteredBankDuplicates duplicate bank alert(s) hidden.',
                ),
              Text(
                _showNeedsReview
                    ? 'Showing ${items.length} of $_reviewTotal emails needing review'
                    : '${items.length} possible expenses to review',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final total in totals.entries)
                Text('${total.key} ${formatFullCurrency(total.value, '')}'),
              for (final item in items)
                Card(
                  child: ExpansionTile(
                    key: ValueKey('email-${item.id}'),
                    initiallyExpanded: _expandedItems.contains(item.id),
                    onExpansionChanged: (expanded) => setState(() {
                      expanded
                          ? _expandedItems.add(item.id)
                          : _expandedItems.remove(item.id);
                    }),
                    leading: Checkbox(
                      value: _selected.contains(item.id),
                      onChanged: _busy || item.currency != _currency
                          ? null
                          : (value) => setState(() {
                              value == true
                                  ? _selected.add(item.id)
                                  : _selected.remove(item.id);
                            }),
                    ),
                    title: Text(
                      item.amountMissing
                          ? item.reviewReason == 'amount_conflict'
                                ? '${item.merchant} · conflicting amounts'
                                : '${item.merchant} · amount format needs review'
                          : item.amountIsSuggestion &&
                                !item.manualReviewConfirmed
                          ? '${item.merchant} · Possible ${item.currency} ${item.amount.toStringAsFixed(2)} — verify'
                          : '${item.merchant} · ${item.currency} ${item.amount.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.date} · ${item.needsReview && !item.manualReviewConfirmed ? emailReviewReason(item.reviewReason) : 'Tap to review or edit'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: [
                      if (_expandedItems.contains(item.id)) ...[
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _classificationFields(item),
                        ),
                        if (item.possibleDuplicate || item.importUncertain)
                          CheckboxListTile(
                            value: item.importAnyway,
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                    () => _edits[item.id] = item.classified(
                                      importAnyway: value ?? false,
                                      edited: false,
                                    ),
                                  ),
                            title: const Text(
                              'Import anyway — I checked that this is a separate or missing expense',
                            ),
                            subtitle: const Text(
                              'Possible duplicate. Check your Sheet first. An uncertain import cannot be retried for ten minutes.',
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () => _showEmailEvidence(item),
                          icon: const Icon(Icons.mail_outline, size: 18),
                          label: const Text('View email evidence'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _edit(item),
                          child: Text(
                            item.needsReview
                                ? 'Review email & enter expense'
                                : 'Edit merchant, amount or date',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (items.isNotEmpty) ...[
                Text(
                  'Amounts use $_currency from Settings. No currency conversion.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _selected.addAll(
                                items
                                    .where((x) => x.currency == _currency)
                                    .take(50)
                                    .map((x) => x.id),
                              ),
                            ),
                      child: Text(
                        _showNeedsReview
                            ? 'Select review emails (up to 50)'
                            : 'Select $_currency (up to 50)',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () async {
                              await _action(
                                () => widget.service
                                    .request(
                                      'exclude',
                                      data: {'ids': _selected.toList()},
                                    )
                                    .then((_) {
                                      _selected.clear();
                                    }),
                              );
                              await _load(clearError: false);
                            },
                      child: const Text('Exclude selected'),
                    ),
                    FilledButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () async {
                              await _action(() async {
                                if (items.any(
                                  (x) =>
                                      _selected.contains(x.id) &&
                                      x.reviewBlocked,
                                ))
                                  throw StateError(
                                    'Exclude drafts that could not be safely re-read; check the email and add them manually.',
                                  );
                                if (items.any(
                                  (x) =>
                                      _selected.contains(x.id) &&
                                      x.needsReview &&
                                      !x.manualReviewConfirmed,
                                ))
                                  throw StateError(
                                    'Open each selected email needing review, enter the correct details and confirm that the payment completed.',
                                  );
                                final result = await widget.onReview(
                                  items
                                      .where((x) => _selected.contains(x.id))
                                      .toList(),
                                  _currency,
                                );
                                if (mounted) setState(() => _message = result);
                              });
                              await _load(clearError: false);
                            },
                      child: const Text('Approve & add to Sheets'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
