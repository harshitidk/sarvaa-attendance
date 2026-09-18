import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _timezone = TextEditingController();
  final _workdayStart = TextEditingController();
  final _workdayEnd = TextEditingController();
  final _absenceCutoff = TextEditingController();
  final _grace = TextEditingController();
  final _retention = TextEditingController();

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
    _workdayStart.dispose();
    _workdayEnd.dispose();
    _absenceCutoff.dispose();
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
      _workdayStart.text = settings.workdayStart;
      _workdayEnd.text = settings.workdayEnd;
      _absenceCutoff.text = settings.absenceCutoff;
      _grace.text = settings.exitGraceSeconds.toString();
      _retention.text = settings.eventRetentionDays.toString();
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
      _error = null;
    });
    try {
      await widget.api.updateSettings(
        companyTimezone: _timezone.text.trim(),
        workdayStart: _workdayStart.text.trim(),
        workdayEnd: _workdayEnd.text.trim(),
        absenceCutoff: _absenceCutoff.text.trim(),
        exitGraceSeconds: int.tryParse(_grace.text.trim()) ?? 300,
        eventRetentionDays: int.tryParse(_retention.text.trim()) ?? 180,
      );
      if (mounted) setState(() => _message = 'Settings saved.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
        TextField(controller: _timezone, decoration: const InputDecoration(labelText: 'Company timezone')),
        const SizedBox(height: 12),
        TextField(controller: _workdayStart, decoration: const InputDecoration(labelText: 'Workday start (HH:MM)')),
        const SizedBox(height: 12),
        TextField(controller: _workdayEnd, decoration: const InputDecoration(labelText: 'Workday end (HH:MM)')),
        const SizedBox(height: 12),
        TextField(controller: _absenceCutoff, decoration: const InputDecoration(labelText: 'Absence cutoff (HH:MM)')),
        const SizedBox(height: 12),
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
}
