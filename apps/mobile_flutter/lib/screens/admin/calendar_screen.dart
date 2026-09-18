import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Holiday> _holidays = const [];
  List<WfhRow> _wfh = const [];
  List<EmployeeRow> _employees = const [];
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
      final results = await Future.wait([
        widget.api.fetchHolidays(),
        widget.api.fetchWfh(),
        widget.api.fetchEmployees(),
      ]);
      if (!mounted) return;
      setState(() {
        _holidays = results[0] as List<Holiday>;
        _wfh = results[1] as List<WfhRow>;
        _employees = results[2] as List<EmployeeRow>;
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

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _addHoliday() async {
    final name = TextEditingController();
    var date = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New holiday',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
                child: Text('Date: ${_iso(date)}'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (name.text.trim().isEmpty) return;
                        await widget.api.createHoliday(name: name.text.trim(), date: _iso(date));
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    if (saved == true) await _load();
  }

  Future<void> _addWfh() async {
    if (_employees.isEmpty) return;
    final reason = TextEditingController();
    var userId = _employees.first.id;
    var date = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign work from home',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: userId,
                decoration: const InputDecoration(labelText: 'Employee'),
                items: _employees
                    .map((employee) =>
                        DropdownMenuItem(value: employee.id, child: Text(employee.name)))
                    .toList(),
                onChanged: (value) => setSheetState(() => userId = value ?? userId),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
                child: Text('Date: ${_iso(date)}'),
              ),
              const SizedBox(height: 12),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await widget.api.createWfh(
                          userId: userId,
                          date: _iso(date),
                          reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
                        );
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    reason.dispose();
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: 'Holidays'), Tab(text: 'WFH')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _holidayList(),
                _wfhList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _holidayList() {
    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _holidays.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final holiday = _holidays[index];
          return ListTile(
            title: Text(holiday.name),
            subtitle: Text(holiday.date),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () async {
                await widget.api.deleteHoliday(holiday.id);
                await _load();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addHoliday,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _wfhList() {
    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _wfh.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = _wfh[index];
          return ListTile(
            title: Text(entry.employeeName.isEmpty ? entry.userId : entry.employeeName),
            subtitle: Text('${entry.date}${entry.reason != null ? ' · ${entry.reason}' : ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () async {
                await widget.api.deleteWfh(entry.id);
                await _load();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addWfh,
        child: const Icon(Icons.add),
      ),
    );
  }
}
