import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<EmployeeRow> _employees = const [];
  List<Map<String, dynamic>> _locations = const [];
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
        widget.api.fetchEmployees(),
        widget.api.fetchLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _employees = results[0] as List<EmployeeRow>;
        _locations = results[1] as List<Map<String, dynamic>>;
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

  Future<void> _edit(EmployeeRow employee) async {
    var role = employee.role;
    var status = employee.status;
    var locationId = employee.locationId;
    final department = TextEditingController(text: employee.department ?? '');

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
              Text(employee.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('${employee.employeeId} · ${employee.email}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const ['employee', 'admin']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setSheetState(() => role = value ?? role),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const ['active', 'inactive']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setSheetState(() => status = value ?? status),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: locationId,
                decoration: const InputDecoration(labelText: 'Office'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                  ..._locations.map(
                    (location) => DropdownMenuItem<String?>(
                      value: location['id'] as String,
                      child: Text(location['name'] as String),
                    ),
                  ),
                ],
                onChanged: (value) => setSheetState(() => locationId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: department,
                decoration: const InputDecoration(labelText: 'Department'),
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
                        await widget.api.updateEmployee(
                          employee.id,
                          role: role,
                          status: status,
                          locationId: locationId,
                          department: department.text.trim(),
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
    department.dispose();
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _employees.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final employee = _employees[index];
          return ListTile(
            title: Text(employee.name),
            subtitle: Text('${employee.employeeId} · ${employee.email}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(employee.role,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: employee.role == 'admin' ? AppColors.primary : AppColors.muted,
                    )),
                Text(employee.status,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
            onTap: () => _edit(employee),
          );
        },
      ),
    );
  }
}
