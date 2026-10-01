import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

/// Employee work-from-home and leave requests awaiting a decision.
///
/// Approving here is the only thing that turns a request into an actual WFH or
/// LEAVE day — the backend materialises what the attendance engine reads.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<WfhRequestRow> _wfhRows = const [];
  List<LeaveRequestRow> _leaveRows = const [];
  String _tab = 'wfh';
  bool _loading = true;
  String? _error;
  String? _busyId;

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
      final results = await Future.wait([
        widget.api.fetchWfhRequests(),
        widget.api.fetchLeaveRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _wfhRows = results[0] as List<WfhRequestRow>;
        _leaveRows = results[1] as List<LeaveRequestRow>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _decide({
    required String id,
    required String name,
    required String date,
    required String kindLabel,
    required bool approve,
  }) async {
    final note = await showAppSheet<String>(
      context,
      builder: (context) => _DecisionSheet(
        name: name,
        date: date,
        kindLabel: kindLabel,
        approve: approve,
      ),
    );
    if (note == null || !mounted) return;

    setState(() => _busyId = id);
    try {
      if (_tab == 'wfh') {
        await widget.api.reviewWfhRequest(
          requestId: id,
          approve: approve,
          note: note,
        );
      } else {
        await widget.api.reviewLeaveRequest(
          requestId: id,
          approve: approve,
          note: note,
        );
      }
      await _load();
      if (mounted) showToast(context, approve ? 'Approved' : 'Declined');
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeError(error));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWfh = _tab == 'wfh';
    final rows = isWfh ? _wfhRows.length : _leaveRows.length;

    return ScreenState(
      loading: _loading,
      error: _error,
      onRetry: _load,
      isEmpty: rows == 0,
      empty: EmptyState(
        icon: isWfh ? Icons.house_outlined : Icons.event_busy_outlined,
        title: 'No requests yet',
        message: isWfh
            ? 'When someone asks to work from home, it lands here for you to approve.'
            : 'When someone asks for leave, it lands here for you to approve.',
      ),
      child: Refreshable(
        onRefresh: _load,
        child: ListView(
          padding: AppPadding.page,
          children: [
            Segmented(
              options: const {'wfh': 'Work from home', 'leave': 'Leave'},
              value: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            const SizedBox(height: Insets.lg),
            if (isWfh) ..._wfhSection() else ..._leaveSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _wfhSection() {
    final pending = _wfhRows.where((row) => row.isPending).toList();
    final decided = _wfhRows.where((row) => !row.isPending).take(30).toList();
    return [
      if (pending.isEmpty)
        const Notice('Nothing waiting on you. Decided requests are below.')
      else ...[
        Eyebrow('${pending.length} awaiting your decision'),
        const SizedBox(height: Insets.sm),
        for (final row in pending) ...[
          _RequestCard(
            name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
            subtitle: formatBusinessDate(row.date, 'EEEE, d MMMM y'),
            reason: row.reason,
            busy: _busyId == row.id,
            onApprove: () => _decide(
              id: row.id,
              name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
              date: row.date,
              kindLabel: 'work from home',
              approve: true,
            ),
            onDecline: () => _decide(
              id: row.id,
              name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
              date: row.date,
              kindLabel: 'work from home',
              approve: false,
            ),
          ),
          const SizedBox(height: Insets.md),
        ],
      ],
      if (decided.isNotEmpty) ...[
        const SizedBox(height: Insets.lg),
        GroupedList(
          title: 'Recently decided',
          children: [
            for (final row in decided)
              AppRow(
                leading: IconTile(
                  row.status == 'approved'
                      ? Icons.check_rounded
                      : Icons.close_rounded,
                  size: 32,
                ),
                title: row.employeeName.isEmpty
                    ? row.employeeCode
                    : row.employeeName,
                subtitle: '${formatBusinessDate(row.date, 'd MMM y')}'
                    ' · ${row.status}',
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _leaveSection() {
    final pending = _leaveRows.where((row) => row.isPending).toList();
    final decided = _leaveRows.where((row) => !row.isPending).take(30).toList();
    return [
      if (pending.isEmpty)
        const Notice('Nothing waiting on you. Decided requests are below.')
      else ...[
        Eyebrow('${pending.length} awaiting your decision'),
        const SizedBox(height: Insets.sm),
        for (final row in pending) ...[
          _RequestCard(
            name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
            subtitle: '${row.leaveType.label} · '
                '${formatBusinessDate(row.date, 'EEEE, d MMMM y')}',
            reason: row.reason,
            busy: _busyId == row.id,
            onApprove: () => _decide(
              id: row.id,
              name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
              date: row.date,
              kindLabel: row.leaveType.label.toLowerCase(),
              approve: true,
            ),
            onDecline: () => _decide(
              id: row.id,
              name: row.employeeName.isEmpty ? row.employeeCode : row.employeeName,
              date: row.date,
              kindLabel: row.leaveType.label.toLowerCase(),
              approve: false,
            ),
          ),
          const SizedBox(height: Insets.md),
        ],
      ],
      if (decided.isNotEmpty) ...[
        const SizedBox(height: Insets.lg),
        GroupedList(
          title: 'Recently decided',
          children: [
            for (final row in decided)
              AppRow(
                leading: IconTile(
                  row.status == 'approved'
                      ? Icons.check_rounded
                      : Icons.close_rounded,
                  size: 32,
                ),
                title: row.employeeName.isEmpty
                    ? row.employeeCode
                    : row.employeeName,
                subtitle: '${row.leaveType.label} · '
                    '${formatBusinessDate(row.date, 'd MMM y')}'
                    ' · ${row.status}',
              ),
          ],
        ),
      ],
    ];
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.name,
    required this.subtitle,
    required this.reason,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final String name;
  final String subtitle;
  final String? reason;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: name),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.subhead),
                    Text(subtitle, style: AppText.bodySm.copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          if (reason != null && reason!.trim().isNotEmpty) ...[
            const SizedBox(height: Insets.lg),
            Text(reason!, style: AppText.body),
          ],
          const SizedBox(height: Insets.lg),
          if (busy)
            const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({
    required this.name,
    required this.date,
    required this.kindLabel,
    required this.approve,
  });

  final String name;
  final String date;
  final String kindLabel;
  final bool approve;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: widget.approve ? 'Approve request' : 'Decline request',
      subtitle: '${widget.name} · '
          '${formatBusinessDate(widget.date, 'EEEE, d MMMM y')}',
      primaryLabel: widget.approve ? 'Approve' : 'Decline',
      onPrimary: () => Navigator.of(context).pop(_note.text),
      children: [
        Notice(
          widget.approve
              ? 'The day becomes ${widget.kindLabel}. It will be marked in '
                  'their calendar and they need not check in.'
              : 'Nothing changes for that day — a check-in is still expected.',
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Note', hint: 'Optional. They will see this.'),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Fine by me.'),
        ),
      ],
    );
  }
}
