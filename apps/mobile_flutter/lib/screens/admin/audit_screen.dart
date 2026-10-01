import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../widgets/common.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchAuditLogs();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Groups entries under a day heading so a long log stays scannable.
  Map<String, List<AuditRow>> get _byDay {
    final grouped = <String, List<AuditRow>>{};
    for (final row in _rows) {
      final key = DateFormat('EEEE, d MMMM y').format(row.createdAt.toLocal());
      grouped.putIfAbsent(key, () => []).add(row);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byDay;

    return ScreenState(
      loading: _loading,
      error: _error,
      onRetry: _load,
      child: _rows.isEmpty
          ? const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Nothing logged yet',
              message: 'Administrative actions are recorded here automatically.',
            )
          : Refreshable(
        onRefresh: _load,
        child: ListView(
                padding: AppPadding.page,
                children: [
                  for (final entry in grouped.entries) ...[
                    GroupedList(
                      title: entry.key,
                      children: [
                        for (final row in entry.value)
                          AppRow(
                            leading: IconTile(_iconFor(row.action), size: 32),
                            title: _humanise(row.action),
                            subtitle: row.entityType,
                            trailing: Text(
                              DateFormat('h:mm a').format(row.createdAt.toLocal()),
                              style: AppText.numeral.copyWith(
                                fontSize: 12.5,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.lg),
                  ],
                ],
              ),
            ),
    );
  }

  IconData _iconFor(String action) {
    final value = action.toLowerCase();
    if (value.contains('delete') || value.contains('remove')) {
      return Icons.delete_outline_rounded;
    }
    if (value.contains('create') || value.contains('insert')) {
      return Icons.add_rounded;
    }
    if (value.contains('update') || value.contains('correct')) {
      return Icons.edit_outlined;
    }
    return Icons.bolt_outlined;
  }

  String _humanise(String action) {
    if (action.isEmpty) return 'Action';
    final words = action.replaceAll('_', ' ').toLowerCase();
    return words[0].toUpperCase() + words.substring(1);
  }
}
