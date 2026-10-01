import 'package:flutter_test/flutter_test.dart';

import 'package:geoattend/models/models.dart';
import 'package:geoattend/utils/attendance_logic.dart';

Geofence _fence({
  String id = 'f1',
  String name = 'Narmada Apartment',
  double lat = 28.6304,
  double lon = 77.2177,
  int radius = 150,
}) {
  return Geofence(
    id: id,
    name: name,
    latitude: lat,
    longitude: lon,
    radiusMeters: radius,
    active: true,
  );
}

void main() {
  group('distanceMeters', () {
    test('is zero for the same point', () {
      expect(distanceMeters(28.6304, 77.2177, 28.6304, 77.2177), 0);
    });

    test('approximates one degree of latitude as ~111 km', () {
      final d = distanceMeters(28.0, 77.0, 29.0, 77.0);
      expect(d, closeTo(111195, 500));
    });
  });

  group('evaluateCheckIn', () {
    test('allows a check-in from inside the fence', () {
      final decision = evaluateCheckIn(
        latitude: 28.6304,
        longitude: 77.2177,
        geofences: [_fence()],
      );
      expect(decision.allowed, isTrue);
      expect(decision.fence?.id, 'f1');
      expect(decision.error, isNull);
    });

    test('allows a point 100 m away when the radius is 150 m', () {
      // ~100 m north of the centre.
      final decision = evaluateCheckIn(
        latitude: 28.6304 + 100 / 111320,
        longitude: 77.2177,
        geofences: [_fence()],
      );
      expect(decision.allowed, isTrue);
    });

    test('rejects a point ~200 m away when the radius is 150 m', () {
      final decision = evaluateCheckIn(
        latitude: 28.6304 + 200 / 111320,
        longitude: 77.2177,
        geofences: [_fence()],
      );
      expect(decision.allowed, isFalse);
      expect(decision.error, contains('Narmada Apartment'));
      expect(decision.error, contains('Move inside'));
      expect(decision.distance, greaterThan(150));
    });

    test('rejects a check-in kilometres away', () {
      final decision = evaluateCheckIn(
        latitude: 28.7000,
        longitude: 77.3000,
        geofences: [_fence()],
      );
      expect(decision.allowed, isFalse);
      expect(decision.distance, greaterThan(10000));
    });

    test('rejects when no workplace is assigned', () {
      final decision = evaluateCheckIn(
        latitude: 28.6304,
        longitude: 77.2177,
        geofences: const [],
      );
      expect(decision.allowed, isFalse);
      expect(decision.error, CheckInDecision.noWorkplace);
    });

    test('rejects a mocked location even when inside the fence', () {
      final decision = evaluateCheckIn(
        latitude: 28.6304,
        longitude: 77.2177,
        geofences: [_fence()],
        isMocked: true,
      );
      expect(decision.allowed, isFalse);
      expect(decision.error, CheckInDecision.mocked);
    });

    test('picks the nearest of several fences', () {
      final near = _fence(id: 'near', name: 'Near', lat: 28.6305, lon: 77.2178);
      final far = _fence(id: 'far', name: 'Far', lat: 12.9352, lon: 77.6245);
      final decision = evaluateCheckIn(
        latitude: 28.6304,
        longitude: 77.2177,
        geofences: [far, near],
      );
      expect(decision.allowed, isTrue);
      expect(decision.fence?.id, 'near');
    });

    test('a location far from every fence is rejected against the nearest', () {
      final delhi = _fence(id: 'delhi', name: 'Delhi HQ', lat: 28.6304, lon: 77.2177);
      final blr = _fence(id: 'blr', name: 'Bengaluru', lat: 12.9352, lon: 77.6245);
      // ~70 km from Delhi, far from Bengaluru: outside both, nearest is Delhi.
      final decision = evaluateCheckIn(
        latitude: 28.0,
        longitude: 77.0,
        geofences: [delhi, blr],
      );
      expect(decision.allowed, isFalse);
      expect(decision.fence?.id, 'delhi');
    });
  });
}
