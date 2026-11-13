import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class DailyReminderSettingsDialog extends StatefulWidget {
  const DailyReminderSettingsDialog({
    super.key,
    required this.enabled,
    required this.time,
    required this.onEnabledChanged,
    required this.onTimeChanged,
    this.onSendTest,
    this.onCheckStatus,
    this.nextReminder,
  });

  final bool enabled;
  final TimeOfDay time;
  final Future<bool> Function(bool enabled) onEnabledChanged;
  final Future<void> Function(TimeOfDay time) onTimeChanged;
  final Future<void> Function()? onSendTest;
  final Future<String> Function()? onCheckStatus;
  final DateTime? Function()? nextReminder;

  @override
  State<DailyReminderSettingsDialog> createState() =>
      _DailyReminderSettingsDialogState();
}

class _DailyReminderSettingsDialogState
    extends State<DailyReminderSettingsDialog> {
  late bool _enabled = widget.enabled;
  late TimeOfDay _time = widget.time;
  String? _errorMessage;
  bool _isUpdating = false;
  String? _status;
  String? _testResult;
  String? _confirmation;
  DateTime? _confirmedNext;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (widget.onCheckStatus == null) return;
    try {
      final status = await widget.onCheckStatus!();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not check reminder: $error');
    }
  }

  Future<void> _sendTest() async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _testResult = null;
    });
    try {
      await widget.onSendTest!();
      if (mounted) {
        setState(
          () => _testResult = 'Test sent to your phone. Check Notification Centre; Focus or notification settings may silence it.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not send test: $error');
      }
    } finally {
      await _checkStatus();
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _confirmation = null;
      _confirmedNext = null;
      _testResult = null;
    });
    try {
      final permissionGranted = await widget.onEnabledChanged(enabled);
      if (!mounted) return;
      setState(() {
        if (permissionGranted) {
          _enabled = enabled;
          _confirmation = enabled
              ? 'Reminder set successfully.'
              : 'Reminder turned off.';
          _confirmedNext = enabled ? widget.nextReminder?.call() : null;
        } else {
          _errorMessage =
              'Notification permission is required to enable reminders.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not update reminder: $error');
      }
    } finally {
      await _checkStatus();
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _chooseTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (selectedTime == null || !mounted) return;

    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _confirmation = null;
      _confirmedNext = null;
      _testResult = null;
    });
    try {
      await widget.onTimeChanged(selectedTime);
      if (mounted) {
        setState(() {
          _time = selectedTime;
          _confirmation = _enabled
              ? 'Reminder set successfully.'
              : 'Time saved. Turn on the reminder to schedule it.';
          _confirmedNext = _enabled ? widget.nextReminder?.call() : null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save reminder time: $error');
      }
    } finally {
      await _checkStatus();
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Daily Expense Reminder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Get a reminder to log daily expenses.'),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable daily reminder'),
              value: _enabled,
              onChanged: _isUpdating ? null : _setEnabled,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !_isUpdating,
              title: const Text('Reminder time'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.access_time),
              onTap: _isUpdating ? null : _chooseTime,
            ),
            if (_confirmation != null) ...[
              const SizedBox(height: 8),
              Text(
                _confirmation!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_confirmedNext != null) ...[
                const SizedBox(height: 4),
                Text(_nextReminderText(context, _confirmedNext!)),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                  const Text(
                    'Android may deliver later.',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ] else if (_status != null)
              Text(_status!),
            if (widget.onSendTest != null)
              TextButton.icon(
                onPressed: _isUpdating ? null : _sendTest,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send test notification'),
              ),
            if (_testResult != null) Text(_testResult!),
            if (_isUpdating) const LinearProgressIndicator(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  String _nextReminderText(BuildContext context, DateTime date) {
    final localizations = MaterialLocalizations.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(date);
    final relative = day == today
        ? 'Today, '
        : day == DateTime(today.year, today.month, today.day + 1)
        ? 'Tomorrow, '
        : '';
    final time = TimeOfDay.fromDateTime(date).format(context);
    return 'Next reminder: $relative${localizations.formatMediumDate(date)} at $time (${date.timeZoneName}).';
  }
}
