import 'package:geofence_service/geofence_service.dart' as gs;

import '../models/models.dart';
import 'api.dart';
import 'notification_service.dart';

/// Wraps the native geofencing plugin and reports transitions to the backend.
///
/// The database remains authoritative: the client only reports an ENTER/EXIT
/// and reflects the returned state. Dedupe keys are minute-bucketed so OS
/// redeliveries of the same transition collapse.
class GeofencingService {
  GeofencingService(this._api);

  final Api _api;

  final gs.GeofenceService _service = gs.GeofenceService.instance.setup(
    // Battery-conscious: geofences are checked about once a minute and a
    // transition is confirmed after a short delay, which is ample for an office
    // visit and avoids waking the radio every few seconds.
    interval: 60000,
    accuracy: 100,
    statusChangeDelayMs: 30000,
    useActivityRecognition: true,
    allowMockLocations: false,
    printDevLog: false,
  );

  bool _listenerAttached = false;

  bool get isRunning => _service.isRunningService;

  void _attachListeners() {
    if (_listenerAttached) return;
    _service.addGeofenceStatusChangeListener(_onStatusChange);
    _service.addStreamErrorListener((error) {});
    _listenerAttached = true;
  }

  /// Registers the employee's assigned geofences and (re)starts monitoring.
  Future<void> sync(List<Geofence> geofences) async {
    _attachListeners();
    if (_service.isRunningService) {
      await _service.stop();
    }
    if (geofences.isEmpty) return;
    await _service.start(
      geofences
          .map(
            (fence) => gs.Geofence(
              id: fence.id,
              latitude: fence.latitude,
              longitude: fence.longitude,
              radius: [
                gs.GeofenceRadius(
                  id: fence.id,
                  length: fence.radiusMeters.toDouble(),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Future<void> stop() async {
    if (_service.isRunningService) {
      await _service.stop();
    }
  }

  Future<void> _onStatusChange(
    gs.Geofence geofence,
    gs.GeofenceRadius radius,
    gs.GeofenceStatus status,
    gs.Location location,
  ) async {
    if (status == gs.GeofenceStatus.DWELL) return;
    if (location.isMock) return; // never trust a mocked fix
    final eventType = status == gs.GeofenceStatus.ENTER ? 'ENTER' : 'EXIT';
    try {
      await _api.recordLocationEvent(
        geofenceId: geofence.id,
        eventType: eventType,
        occurredAt: DateTime.now().toUtc(),
        accuracyMeters: location.accuracy,
        latitude: location.latitude,
        longitude: location.longitude,
        source: 'OS geofence',
        metadata: const {
          'platform': 'flutter',
          'occurredAtSource': 'delivery',
        },
      );
      if (eventType == 'ENTER') {
        await NotificationService.show('Checked in', 'Presence recorded.');
      } else {
        await NotificationService.show('Checked out', 'Your check-out has been recorded.');
      }
    } catch (_) {
      // Transient failures are safe to ignore; the next transition retries.
    }
  }
}
