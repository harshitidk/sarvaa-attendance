import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// How ready the device is to record attendance on its own.
enum BackgroundReadiness {
  /// Location is off at the OS level; nothing can work.
  servicesDisabled,

  /// No location access at all.
  denied,

  /// Permanently refused — only a trip to system settings can undo it.
  deniedForever,

  /// Foreground only. Manual check-in works; automatic detection does not.
  foregroundOnly,

  /// "Allow all the time" — geofence transitions are delivered.
  always,
}

/// Runtime permissions.
///
/// The manifest *declaring* ACCESS_BACKGROUND_LOCATION and POST_NOTIFICATIONS
/// grants nothing: both must be asked for at runtime, and background location
/// on Android 11+ cannot be granted from a dialog at all — the user has to
/// choose "Allow all the time" in system settings. Without this, automatic
/// attendance silently never fires, which looks like the app being broken.
class PermissionsService {
  const PermissionsService._();

  /// Foreground location, enough for a manual check-in.
  ///
  /// Throws with a readable message when it cannot be obtained, because the
  /// check-in path surfaces that text directly.
  static Future<void> ensureForeground() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission is required to check in.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission was permanently denied. Enable it for this app '
        'in system settings.',
      );
    }
  }

  /// Where the device currently stands, without prompting.
  static Future<BackgroundReadiness> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return BackgroundReadiness.servicesDisabled;
    }
    return _readinessFor(await Geolocator.checkPermission());
  }

  /// Asks for as much as the OS will grant in one go.
  ///
  /// On Android 10 a second request can upgrade whileInUse to always. On 11+
  /// it cannot, so the caller should offer [openSettings] when the result is
  /// still [BackgroundReadiness.foregroundOnly].
  static Future<BackgroundReadiness> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return BackgroundReadiness.servicesDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // A second ask is what promotes whileInUse to always where that is still
    // permitted; on newer Android it is a no-op rather than an error.
    if (permission == LocationPermission.whileInUse && Platform.isAndroid) {
      permission = await Geolocator.requestPermission();
    }

    return _readinessFor(permission);
  }

  static BackgroundReadiness _readinessFor(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => BackgroundReadiness.always,
        LocationPermission.whileInUse => BackgroundReadiness.foregroundOnly,
        LocationPermission.deniedForever => BackgroundReadiness.deniedForever,
        _ => BackgroundReadiness.denied,
      };

  /// Android 13+ and iOS both gate notifications behind a runtime grant.
  /// Returns false when they will not be shown.
  static Future<bool> ensureNotifications() async {
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      if (Platform.isAndroid) {
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios = plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (_) {
      // Never block attendance on a notification grant.
    }
    return false;
  }

  static Future<void> openSettings() => Geolocator.openAppSettings();

  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

/// What to tell the user, per readiness state.
extension BackgroundReadinessCopy on BackgroundReadiness {
  bool get isReady => this == BackgroundReadiness.always;

  String get title => switch (this) {
        BackgroundReadiness.always => 'Automatic attendance is on',
        BackgroundReadiness.foregroundOnly => 'Finish setting up automatic attendance',
        BackgroundReadiness.denied => 'Location permission needed',
        BackgroundReadiness.deniedForever => 'Location permission blocked',
        BackgroundReadiness.servicesDisabled => 'Location is turned off',
      };

  String get message => switch (this) {
        BackgroundReadiness.always =>
          'Your arrivals and departures are recorded for you.',
        BackgroundReadiness.foregroundOnly =>
          'Location is only allowed while the app is open, so arrivals are not '
              'recorded in the background. Set location access to '
              '"Allow all the time".',
        BackgroundReadiness.denied =>
          'Allow location access so the app can record your attendance.',
        BackgroundReadiness.deniedForever =>
          'Location was permanently denied. Enable it for this app in system '
              'settings to record attendance automatically.',
        BackgroundReadiness.servicesDisabled =>
          'Turn on location services to record attendance automatically.',
      };

  /// Null when there is nothing for the user to do.
  String? get actionLabel => switch (this) {
        BackgroundReadiness.always => null,
        BackgroundReadiness.denied => 'Allow location',
        BackgroundReadiness.servicesDisabled => 'Open location settings',
        _ => 'Open settings',
      };
}
