import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';

const _weekdayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _timezone = TextEditingController();
  final _grace = TextEditingController();
  final _retention = TextEditingController();

  String _workdayStart = '09:00';
  String _workdayEnd = '18:00';
  String _absenceCutoff = '12:00';
  Set<int> _workingDays = {1, 2, 3, 4, 5, 6};

  bool _loading = true;
  bool _saving = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timezone.dispose();
    _grace.dispose();
    _retention.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppSettings settings = await widget.api.fetchSettings();
      if (!mounted) return;
      _timezone.text = settings.companyTimezone;
      _grace.text = settings.exitGraceSeconds.toString();
      _retention.text = settings.eventRetentionDays.toString();
      _workdayStart = _normalizeTime(settings.workdayStart, '09:00');
      _workdayEnd = _normalizeTime(settings.workdayEnd, '18:00');
      _absenceCutoff = _normalizeTime(settings.absenceCutoff, '12:00');
      _workingDays = settings.workingDays.toSet();
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _describe(error);
        _loading = false;
      });
    }
  }

  /// Postgres returns `HH:MM:SS`; the picker needs `HH:MM`.
  String _normalizeTime(String value, String fallback) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return fallback;
    final hour = match.group(1)!.padLeft(2, '0');
    return '$hour:${match.group(2)}';
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      ),
    );
    if (picked == null) return;
    onPicked(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _save() async {
    final timezone = _timezone.text.trim();
    final grace = int.tryParse(_grace.text.trim());
    final retention = int.tryParse(_retention.text.trim());

    if (timezone.isEmpty) {
      setState(() => _error = 'Company timezone is required (e.g. Asia/Kolkata).');
      return;
    }
    if (grace == null || grace < 0) {
      setState(() => _error = 'Exit grace must be a number of seconds (0 or more).');
      return;
    }
    if (retention == null || retention <= 0) {
      setState(() => _error = 'Event retention must be a positive number of days.');
      return;
    }
    if (_workingDays.isEmpty) {
      setState(() => _error = 'Select at least one working day.');
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
      _error = null;
    });
    try {
      final saved = await widget.api.updateSettings(
        companyTimezone: timezone,
        workdayStart: _workdayStart,
        workdayEnd: _workdayEnd,
        absenceCutoff: _absenceCutoff,
        exitGraceSeconds: grace,
        eventRetentionDays: retention,
        workingDays: _workingDays.toList()..sort(),
      );
      if (mounted) {
        setState(() {
          if (saved) {
            _message = 'Settings saved.';
          } else {
            _error = 'Settings were not saved. Check that the database migrations '
                'are applied and your account has admin access.';
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Company timezone, working hours, grace period and absence cutoff.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _timezone,
          decoration: const InputDecoration(
            labelText: 'Company timezone',
            hintText: 'Asia/Kolkata',
          ),
        ),
        const SizedBox(height: 16),
        _timeField('Workday start', _workdayStart, (value) => setState(() => _workdayStart = value)),
        const SizedBox(height: 12),
        _timeField('Workday end', _workdayEnd, (value) => setState(() => _workdayEnd = value)),
        const SizedBox(height: 12),
        _timeField('Absence cutoff', _absenceCutoff, (value) => setState(() => _absenceCutoff = value)),
        const SizedBox(height: 20),
        const Text('Working days', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Absence is only marked on these days. Individual days can still be overridden per employee with a holiday or WFH.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _weekdayLabels.entries.map((entry) {
            final selected = _workingDays.contains(entry.key);
            return FilterChip(
              label: Text(entry.value),
              selected: selected,
              onSelected: (value) {
                setState(() {
                  if (value) {
                    _workingDays.add(entry.key);
                  } else {
                    _workingDays.remove(entry.key);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _grace,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Exit grace (seconds)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _retention,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Event retention (days)'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryForeground,
                  ),
                )
              : const Text('Save settings'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(color: AppColors.positive)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }

  Widget _timeField(String label, String value, ValueChanged<String> onPicked) {
    return InkWell(
      onTap: () => _pickTime(value, onPicked),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value, style: const TextStyle(fontSize: 16)),
            const Icon(Icons.access_time),
          ],
        ),
      ),
    );
  }
}

String _describe(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
