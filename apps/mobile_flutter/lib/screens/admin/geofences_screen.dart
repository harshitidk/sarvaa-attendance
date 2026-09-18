import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';

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
    final name = TextEditingController(text: geofence?.name ?? '');
    final latitude = TextEditingController(text: geofence?.latitude.toString() ?? '');
    final longitude = TextEditingController(text: geofence?.longitude.toString() ?? '');
    final radius = TextEditingController(text: geofence?.radiusMeters.toString() ?? '150');
    var locationId = geofence?.locationId;
    var active = geofence?.active ?? true;

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
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(geofence == null ? 'New geofence' : 'Edit geofence',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(
                  controller: latitude,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: longitude,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: radius,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Radius (meters)'),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setSheetState(() => active = value),
                ),
                const SizedBox(height: 12),
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
                          final lat = double.tryParse(latitude.text.trim());
                          final lng = double.tryParse(longitude.text.trim());
                          final rad = int.tryParse(radius.text.trim());
                          if (name.text.trim().isEmpty || lat == null || lng == null || rad == null) {
                            return;
                          }
                          await widget.api.saveGeofence(
                            id: geofence?.id,
                            name: name.text.trim(),
                            latitude: lat,
                            longitude: lng,
                            radiusMeters: rad,
                            locationId: locationId,
                            active: active,
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
      ),
    );
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    radius.dispose();
    if (saved == true) await _load();
  }

  Future<void> _delete(Geofence geofence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete geofence?'),
        content: Text(geofence.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.deleteGeofence(geofence.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _geofences.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final geofence = _geofences[index];
                      return ListTile(
                        title: Text(geofence.name),
                        subtitle: Text(
                          '${geofence.latitude}, ${geofence.longitude} · r=${geofence.radiusMeters}m',
                        ),
                        leading: Switch(
                          value: geofence.active,
                          onChanged: (value) async {
                            await widget.api.setGeofenceActive(geofence.id, value);
                            await _load();
                          },
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(geofence),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                              onPressed: () => _delete(geofence),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
