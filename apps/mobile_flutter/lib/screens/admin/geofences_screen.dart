import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';
import '../../widgets/common.dart';

class GeofencesScreen extends StatefulWidget {
  const GeofencesScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<GeofencesScreen> createState() => _GeofencesScreenState();
}

class _GeofencesScreenState extends State<GeofencesScreen> {
  List<Geofence> _geofences = const [];
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
        widget.api.fetchGeofences(),
        widget.api.fetchLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _geofences = results[0] as List<Geofence>;
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

  Future<void> _edit([Geofence? geofence]) async {
    final saved = await showAppSheet<bool>(
      context,
      builder: (context) => _GeofenceSheet(
        api: widget.api,
        geofence: geofence,
        locations: _locations,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        showToast(context, geofence == null ? 'Geofence created' : 'Geofence saved');
      }
    }
  }

  Future<void> _toggle(Geofence geofence, bool active) async {
    // Optimistic: the switch moves now, and rolls back if the write fails.
    final previous = _geofences;
    setState(() {
      _geofences = [
        for (final item in _geofences)
          if (item.id == geofence.id)
            Geofence(
              id: item.id,
              name: item.name,
              latitude: item.latitude,
              longitude: item.longitude,
              radiusMeters: item.radiusMeters,
              active: active,
              locationId: item.locationId,
            )
          else
            item,
      ];
    });
    try {
      await widget.api.setGeofenceActive(geofence.id, active);
    } catch (error) {
      if (!mounted) return;
      setState(() => _geofences = previous);
      showToast(context, 'Could not update: $error');
    }
  }

  Future<void> _delete(Geofence geofence) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete geofence?',
      message: '"${geofence.name}" will stop recording attendance for everyone '
          'assigned to it. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await widget.api.deleteGeofence(geofence.id);
      await _load();
      if (mounted) showToast(context, 'Geofence deleted');
    } catch (error) {
      if (mounted) showToast(context, 'Could not delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: ScreenState(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _geofences.isEmpty
            ? EmptyState(
                icon: Icons.map_outlined,
                title: 'No geofences yet',
                message: 'Add the workplaces where attendance should be recorded.',
                actionLabel: 'Add geofence',
                onAction: _edit,
              )
            : Refreshable(
        onRefresh: _load,
        child: ListView.separated(
                  padding: AppPadding.pageWithFab,
                  itemCount: _geofences.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                  itemBuilder: (context, index) {
                    final geofence = _geofences[index];
                    return _GeofenceCard(
                      geofence: geofence,
                      onEdit: () => _edit(geofence),
                      onDelete: () => _delete(geofence),
                      onToggle: (value) => _toggle(geofence, value),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('New'),
      ),
    );
  }
}

class _GeofenceCard extends StatelessWidget {
  const _GeofenceCard({
    required this.geofence,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Geofence geofence;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: geofence.active ? AppColors.line : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  geofence.name,
                  style: AppText.subhead.copyWith(
                    fontSize: 16,
                    color: geofence.active ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ),
              Switch(value: geofence.active, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Icon(Icons.my_location_rounded, size: 14, color: AppColors.faint),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  '${geofence.latitude.toStringAsFixed(5)}, '
                  '${geofence.longitude.toStringAsFixed(5)}',
                  style: AppText.numeral.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.sunk,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  'r ${geofence.radiusMeters} m',
                  style: AppText.numeral.copyWith(
                    fontSize: 11.5,
                    color: AppColors.ink2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          const Divider(height: 1),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeofenceSheet extends StatefulWidget {
  const _GeofenceSheet({
    required this.api,
    required this.geofence,
    required this.locations,
  });

  final AdminApi api;
  final Geofence? geofence;
  final List<Map<String, dynamic>> locations;

  @override
  State<_GeofenceSheet> createState() => _GeofenceSheetState();
}

class _GeofenceSheetState extends State<_GeofenceSheet> {
  late final _name = TextEditingController(text: widget.geofence?.name ?? '');
  late final _latitude =
      TextEditingController(text: widget.geofence?.latitude.toString() ?? '');
  late final _longitude =
      TextEditingController(text: widget.geofence?.longitude.toString() ?? '');
  late final _radius = TextEditingController(
      text: widget.geofence?.radiusMeters.toString() ?? '150');
  late String? _locationId = widget.geofence?.locationId;
  late bool _active = widget.geofence?.active ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    final radius = int.tryParse(_radius.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Give the workplace a name.');
      return;
    }
    if (latitude == null || latitude < -90 || latitude > 90) {
      setState(() => _error = 'Latitude must be a number between -90 and 90.');
      return;
    }
    if (longitude == null || longitude < -180 || longitude > 180) {
      setState(() => _error = 'Longitude must be a number between -180 and 180.');
      return;
    }
    if (radius == null || radius < 50) {
      setState(() => _error = 'Use a radius of at least 50 m so GPS drift does '
          'not cause false exits.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.saveGeofence(
        id: widget.geofence?.id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radius,
        locationId: _locationId,
        active: _active,
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
      title: widget.geofence == null ? 'New geofence' : 'Edit geofence',
      subtitle: 'Attendance is recorded when an employee crosses this boundary.',
      primaryLabel: widget.geofence == null ? 'Create' : 'Save',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Head office'),
        ),
        const SizedBox(height: Insets.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Latitude'),
                  TextField(
                    controller: _latitude,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(hintText: '12.97160'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Longitude'),
                  TextField(
                    controller: _longitude,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(hintText: '77.59456'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Radius', hint: 'Metres. 150 m suits most offices.'),
        TextField(
          controller: _radius,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'm'),
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
        const SizedBox(height: Insets.lg),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active', style: AppText.subhead.copyWith(fontSize: 14)),
                    Text(
                      'Inactive geofences record nothing.',
                      style: AppText.bodySm.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _active,
                onChanged: _busy ? null : (value) => setState(() => _active = value),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}
