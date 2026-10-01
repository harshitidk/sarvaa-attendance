import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../widgets/common.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _search = TextEditingController();
  List<EmployeeRow> _employees = const [];
  List<Map<String, dynamic>> _locations = const [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  List<EmployeeRow> get _visible {
    if (_query.trim().isEmpty) return _employees;
    final needle = _query.trim().toLowerCase();
    return _employees
        .where((employee) =>
            employee.name.toLowerCase().contains(needle) ||
            employee.employeeId.toLowerCase().contains(needle) ||
            employee.email.toLowerCase().contains(needle) ||
            (employee.department ?? '').toLowerCase().contains(needle))
        .toList();
  }

  Future<void> _edit(EmployeeRow employee) async {
    final saved = await showAppSheet<bool>(
      context,
      builder: (context) => _EmployeeSheet(
        api: widget.api,
        employee: employee,
        locations: _locations,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showToast(context, 'Employee updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = _visible;

    return Column(
      children: [
        Padding(
          padding: AppPadding.bar,
          child: SearchField(
            controller: _search,
            hintText: 'Search employees',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ScreenState(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: employees.isEmpty
                ? const EmptyState(
                    icon: Icons.people_outline,
                    title: 'No employees found',
                    message: 'Adjust your search to see more people.',
                  )
                : Refreshable(
        onRefresh: _load,
        child: ListView(
                      padding: AppPadding.pageBelowBar,
                      children: [
                        GroupedList(
                          children: [
                            for (final employee in employees)
                              AppRow(
                                leading: InitialsAvatar(name: employee.name),
                                title: employee.name.isEmpty
                                    ? employee.employeeId
                                    : employee.name,
                                subtitle: employee.employeeId.isEmpty
                                    ? employee.email
                                    : '${employee.employeeId} · ${employee.email}',
                                trailing: _RolePill(
                                  role: employee.role,
                                  active: employee.status == 'active',
                                ),
                                onTap: () => _edit(employee),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role, required this.active});

  final String role;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 3),
          decoration: BoxDecoration(
            color: isAdmin ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: isAdmin ? AppColors.ink : AppColors.line),
          ),
          child: Text(
            isAdmin ? 'ADMIN' : 'EMPLOYEE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: isAdmin ? AppColors.onInk : AppColors.muted,
            ),
          ),
        ),
        if (!active) ...[
          const SizedBox(height: 4),
          Text(
            'Inactive',
            style: AppText.bodySm.copyWith(fontSize: 11, color: AppColors.faint),
          ),
        ],
      ],
    );
  }
}

class _EmployeeSheet extends StatefulWidget {
  const _EmployeeSheet({
    required this.api,
    required this.employee,
    required this.locations,
  });

  final AdminApi api;
  final EmployeeRow employee;
  final List<Map<String, dynamic>> locations;

  @override
  State<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends State<_EmployeeSheet> {
  late final TextEditingController _department =
      TextEditingController(text: widget.employee.department ?? '');
  late String _role = widget.employee.role;
  late String _status = widget.employee.status;
  late String? _locationId = widget.employee.locationId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _department.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.updateEmployee(
        widget.employee.id,
        role: _role,
        status: _status,
        locationId: _locationId,
        department: _department.text.trim(),
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
      title: widget.employee.name.isEmpty ? 'Employee' : widget.employee.name,
      subtitle: '${widget.employee.employeeId} · ${widget.employee.email}',
      primaryLabel: 'Save changes',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Role'),
        Segmented(
          options: const {'employee': 'Employee', 'admin': 'Admin'},
          value: _role,
          onChanged: _busy ? null : (value) => setState(() => _role = value),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Status'),
        Segmented(
          options: const {'active': 'Active', 'inactive': 'Inactive'},
          value: _status,
          onChanged: _busy ? null : (value) => setState(() => _status = value),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Office'),
        DropdownButtonFormField<String?>(
          initialValue: _locationId,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
            ...widget.locations.map(
              (location) => DropdownMenuItem<String?>(
                value: location['id'] as String,
                child: Text(location['name'] as String),
              ),
            ),
          ],
          onChanged: _busy ? null : (value) => setState(() => _locationId = value),
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Department'),
        TextField(
          controller: _department,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Engineering'),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}

