import 'package:flutter/material.dart';

class DailyReminderSettingsDialog extends StatefulWidget {
  const DailyReminderSettingsDialog({
    super.key,
    required this.enabled,
    required this.time,
    required this.onEnabledChanged,
    required this.onTimeChanged,
  });

  final bool enabled;
  final TimeOfDay time;
  final Future<bool> Function(bool enabled) onEnabledChanged;
  final Future<void> Function(TimeOfDay time) onTimeChanged;

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

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
    });
    try {
      final permissionGranted = await widget.onEnabledChanged(enabled);
      if (!mounted) return;
      setState(() {
        if (permissionGranted) {
          _enabled = enabled;
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
    });
    try {
      await widget.onTimeChanged(selectedTime);
      if (mounted) setState(() => _time = selectedTime);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save reminder time: $error');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Daily Expense Reminder'),
      content: Column(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
