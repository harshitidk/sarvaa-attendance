import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  List<Holiday> _holidays = const [];
  List<WfhRow> _wfh = const [];
  List<CompanyWfhDay> _companyDays = const [];
  List<EmployeeRow> _employees = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.fetchHolidays(),
        widget.api.fetchWfh(),
        widget.api.fetchEmployees(),
        widget.api.fetchCompanyWfhDays(),
      ]);
      if (!mounted) return;
      setState(() {
        _holidays = results[0] as List<Holiday>;
        _wfh = results[1] as List<WfhRow>;
        _employees = results[2] as List<EmployeeRow>;
        _companyDays = results[3] as List<CompanyWfhDay>;
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


  static String _pretty(String isoDate) =>
      formatBusinessDate(isoDate, 'EEE, d MMM y');

  Future<void> _add() async {
    final tab = _tabs.index;
    // Choose first, await once: awaiting inside each branch would use
    // `context` across an async gap.
    final WidgetBuilder builder = switch (tab) {
      0 => (context) => _HolidaySheet(api: widget.api),
      1 => (context) => _CompanyWfhSheet(api: widget.api),
      _ => (context) => _WfhSheet(api: widget.api, employees: _employees),
    };
    final saved = await showAppSheet<bool>(context, builder: builder);
    if (saved == true) {
      await _load();
      if (mounted) {
        showToast(context, switch (tab) {
          0 => 'Holiday added',
          1 => 'Company WFH day set',
          _ => 'WFH assigned',
        });
      }
    }
  }

  Future<void> _clearCompanyDay(CompanyWfhDay day) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove this WFH day?',
      message: '${_pretty(day.date)} goes back to a normal working day and '
          'everyone will be expected to check in. Days granted to individuals '
          'are kept.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await widget.api.clearCompanyWfhDay(day.id);
    await _load();
    if (mounted) showToast(context, 'Company WFH day removed');
  }

  Future<void> _deleteHoliday(Holiday holiday) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove holiday?',
      message: '${holiday.name} on ${_pretty(holiday.date)} will no longer be '
          'treated as a company holiday.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await widget.api.deleteHoliday(holiday.id);
    await _load();
    if (mounted) showToast(context, 'Holiday removed');
  }

  Future<void> _deleteWfh(WfhRow entry) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove WFH?',
      message: 'This work-from-home assignment will be removed.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await widget.api.deleteWfh(entry.id);
    await _load();
    if (mounted) showToast(context, 'WFH removed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Holidays'),
                Tab(text: 'Company WFH'),
                Tab(text: 'Per employee'),
              ],
            ),
          ),
          Expanded(
            child: ScreenState(
              loading: _loading,
              error: _error,
              onRetry: _load,
              child: TabBarView(
                controller: _tabs,
                children: [_holidayList(), _companyList(), _wfhList()],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(switch (_tabs.index) {
          0 => 'Holiday',
          1 => 'WFH day',
          _ => 'Assign',
        }),
      ),
    );
  }

  Widget _holidayList() {
    if (_holidays.isEmpty) {
      return const EmptyState(
        icon: Icons.wb_sunny_outlined,
        title: 'No holidays set',
        message: 'Company holidays take priority over office attendance.',
      );
    }
    return Refreshable(
        onRefresh: _load,
        child: ListView(
        padding: AppPadding.pageWithFab,
        children: [
          GroupedList(
            children: [
              for (final holiday in _holidays)
                AppRow(
                  leading: const IconTile(Icons.wb_sunny_outlined),
                  title: holiday.name,
                  subtitle: _pretty(holiday.date),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    tooltip: 'Remove',
                    onPressed: () => _deleteHoliday(holiday),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dates the whole company works from home — nobody needs to check in.
  Widget _companyList() {
    if (_companyDays.isEmpty) {
      return const EmptyState(
        icon: Icons.house_outlined,
        title: 'No company WFH days',
        message: 'Mark a date and every active employee is excused from '
            'checking in that day.',
      );
    }
    return Refreshable(
      onRefresh: _load,
      child: ListView(
        padding: AppPadding.pageWithFab,
        children: [
          const ScreenCaption(
            'Everyone active is marked as working from home on these dates.',
          ),
          GroupedList(
            children: [
              for (final day in _companyDays)
                AppRow(
                  leading: const IconTile(Icons.house_outlined),
                  title: _pretty(day.date),
                  subtitle: day.note == null || day.note!.trim().isEmpty
                      ? 'Whole company'
                      : day.note,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    tooltip: 'Remove',
                    onPressed: () => _clearCompanyDay(day),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wfhList() {
    if (_wfh.isEmpty) {
      return const EmptyState(
        icon: Icons.house_outlined,
        title: 'No WFH assignments',
        message: 'Assign a day and the employee is marked as working from home.',
      );
    }
    return Refreshable(
        onRefresh: _load,
        child: ListView(
        padding: AppPadding.pageWithFab,
        children: [
          GroupedList(
            children: [
              for (final entry in _wfh)
                AppRow(
                  leading: const IconTile(Icons.house_outlined),
                  title: entry.employeeName.isEmpty ? entry.userId : entry.employeeName,
                  subtitle: entry.reason == null || entry.reason!.trim().isEmpty
                      ? _pretty(entry.date)
                      : '${_pretty(entry.date)} · ${entry.reason}',
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    tooltip: 'Remove',
                    onPressed: () => _deleteWfh(entry),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tappable date field used inside the add sheets.
class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap, this.enabled = true});

  final DateTime value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, d MMMM y').format(value),
                style: AppText.numeral.copyWith(fontSize: 15),
              ),
            ),
            Icon(Icons.calendar_today_outlined, size: 17, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _HolidaySheet extends StatefulWidget {
  const _HolidaySheet({required this.api});

  final AdminApi api;

  @override
  State<_HolidaySheet> createState() => _HolidaySheetState();
}

class _HolidaySheetState extends State<_HolidaySheet> {
  final _name = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name the holiday.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.createHoliday(
        name: name,
        date: isoDate(_date),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'New holiday',
      subtitle: 'Holidays take priority over office attendance for everyone.',
      primaryLabel: 'Add holiday',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Independence Day'),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Date'),
        _DateField(value: _date, onTap: _pickDate, enabled: !_busy),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}

class _WfhSheet extends StatefulWidget {
  const _WfhSheet({required this.api, required this.employees});

  final AdminApi api;
  final List<EmployeeRow> employees;

  @override
  State<_WfhSheet> createState() => _WfhSheetState();
}

class _WfhSheetState extends State<_WfhSheet> {
  final _reason = TextEditingController();
  late String? _userId =
      widget.employees.isEmpty ? null : widget.employees.first.id;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _error = 'No employees available to assign.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.createWfh(
        userId: userId,
        date: isoDate(_date),
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Assign work from home',
      subtitle: 'The employee is marked WFH for the day, with no geofence needed.',
      primaryLabel: 'Assign',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Employee'),
        DropdownButtonFormField<String?>(
          initialValue: _userId,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
          ),
          items: [
            for (final employee in widget.employees)
              DropdownMenuItem<String?>(
                value: employee.id,
                child: Text(
                  employee.name.isEmpty ? employee.employeeId : employee.name,
                ),
              ),
          ],
          onChanged: _busy ? null : (value) => setState(() => _userId = value),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Date'),
        _DateField(value: _date, onTap: _pickDate, enabled: !_busy),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Reason', hint: 'Optional.'),
        TextField(
          controller: _reason,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Client visit in the morning'),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}

class _CompanyWfhSheet extends StatefulWidget {
  const _CompanyWfhSheet({required this.api});

  final AdminApi api;

  @override
  State<_CompanyWfhSheet> createState() => _CompanyWfhSheetState();
}

class _CompanyWfhSheetState extends State<_CompanyWfhSheet> {
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.setCompanyWfhDay(
        date: isoDate(_date),
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeError(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Company WFH day',
      subtitle: 'Every active employee is marked as working from home, so no '
          'one needs to check in.',
      primaryLabel: 'Set day',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Date'),
        _DateField(value: _date, onTap: _pickDate, enabled: !_busy),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Note', hint: 'Optional. Shown on the record.'),
        TextField(
          controller: _note,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Office fumigation'),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}
