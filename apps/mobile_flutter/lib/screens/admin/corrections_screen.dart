import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../widgets/common.dart';

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
    return ScreenState(
      loading: _loading,
      error: _error,
      onRetry: _load,
      child: _rows.isEmpty
          ? const EmptyState(
              icon: Icons.build_outlined,
              title: 'No corrections yet',
              message: 'Manual changes to attendance records will be listed here.',
            )
          : Refreshable(
        onRefresh: _load,
        child: ListView.separated(
                padding: AppPadding.page,
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                itemBuilder: (context, index) => _CorrectionCard(row: _rows[index]),
              ),
            ),
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({required this.row});

  final CorrectionRow row;

  @override
  Widget build(BuildContext context) {
    final oldStatus = row.oldValue['status'] as String?;
    final newStatus = row.newValue['status'] as String?;

    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (oldStatus != null || newStatus != null) ...[
            Row(
              children: [
                if (oldStatus != null) StatusBadge(status: oldStatus, compact: true),
                if (oldStatus != null && newStatus != null)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Insets.sm),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppColors.faint,
                    ),
                  ),
                if (newStatus != null) StatusBadge(status: newStatus, compact: true),
              ],
            ),
            const SizedBox(height: Insets.lg),
          ],
          Text(row.reason, style: AppText.body.copyWith(color: AppColors.ink)),
          const SizedBox(height: Insets.md),
          Text(
            DateFormat('d MMM y, h:mm a').format(row.createdAt.toLocal()),
            style: AppText.bodySm.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
