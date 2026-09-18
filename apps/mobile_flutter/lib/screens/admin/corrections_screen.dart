import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';

class CorrectionsScreen extends StatefulWidget {
  const CorrectionsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<CorrectionsScreen> createState() => _CorrectionsScreenState();
}

class _CorrectionsScreenState extends State<CorrectionsScreen> {
  List<CorrectionRow> _rows = const [];
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
      final rows = await widget.api.fetchCorrections();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_rows.isEmpty) {
      return const Center(
        child: Text('No corrections yet.', style: TextStyle(color: AppColors.muted)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = _rows[index];
          final oldStatus = row.oldValue['status'];
          final newStatus = row.newValue['status'];
          return ListTile(
            title: Text(row.reason),
            subtitle: Text('$oldStatus → $newStatus\n${row.createdAt.toLocal()}'),
            isThreeLine: true,
          );
        },
      ),
    );
  }
}
