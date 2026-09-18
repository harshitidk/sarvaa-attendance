import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/geofencing_service.dart';
import '../state/auth_controller.dart';
import '../utils/attendance_logic.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.geofencing,
  });

  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSettings _settings = const AppSettings();
  List<Geofence> _geofences = const [];
  List<LocationEvent> _events = const [];
  Attendance? _today;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  String? _error;

  String get _timezone => _settings.companyTimezone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    try {
      final settings = await widget.api.fetchAppSettings();
      final results = await Future.wait([
        widget.api.fetchAssignedGeofences(),
        widget.api.fetchTodayAttendance(userId, settings.companyTimezone),
        widget.api.fetchRecentEvents(userId, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _geofences = results[0] as List<Geofence>;
        _today = results[1] as Attendance?;
        _events = results[2] as List<LocationEvent>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _describe(error);
        _loading = false;
      });
    }
  }

  Geofence? get _nearestGeofence {
    if (_geofences.isEmpty) return null;
    return _geofences.first;
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('Location services are turned off.');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to check in.');
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _checkIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final previous = _today;
    try {
      final position = await _currentPosition();
      final fence = _nearestGeofence;
      if (fence == null) {
        throw Exception('No geofence is assigned to your account.');
      }
      final distance = distanceMeters(
        position.latitude,
        position.longitude,
        fence.latitude,
        fence.longitude,
      );
      if (distance > fence.radiusMeters) {
        throw Exception(
          'You are about ${distance.round()} m from ${fence.name}. Move inside to check in.',
        );
      }
      final now = DateTime.now().toUtc();
      if (previous != null) {
        setState(() => _today = previous.copyWith(
              status: 'PRESENT',
              checkInAt: previous.checkInAt ?? now,
              clearCheckOut: true,
              totalDurationSeconds: 0,
            ));
      }
      await widget.api.recordLocationEvent(
        geofenceId: fence.id,
        eventType: 'ENTER',
        occurredAt: now,
        accuracyMeters: position.accuracy,
        source: 'Mobile geolocation',
        metadata: const {'platform': 'flutter', 'note': 'explicit check-in'},
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _today = previous;
          _error = _describe(error);
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) setState(() => _message = 'Check-in recorded.');
  }

  Future<void> _submitCheckout({required bool isUpdate}) async {
    final current = _today;
    if (current == null || current.id.isEmpty) {
      setState(() => _error = 'Check in before checking out.');
      return;
    }
    final summary = await showCheckoutSheet(
      context,
      initialSummary: current.workSummary ?? '',
      isUpdate: isUpdate,
    );
    if (summary == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _today = _optimisticCheckout(current, summary);
    });
    final previous = current;
    try {
      await widget.api.employeeCheckOut(
        attendanceId: current.id,
        summary: summary,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _today = previous;
          _error = _describe(error);
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) setState(() => _message = 'Check-out recorded.');
  }

  Attendance _optimisticCheckout(Attendance current, String summary) {
    final checkOutAt = current.checkOutAt ?? DateTime.now().toUtc();
    return current.copyWith(
      status: 'CHECKED_OUT',
      checkOutAt: checkOutAt,
      workSummary: summary,
      totalDurationSeconds: current.checkInAt == null
          ? current.totalDurationSeconds
          : durationSeconds(current.checkInAt!, checkOutAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final tone = toneFor(_today?.status);
    final today = _today;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: tone.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel(today?.status),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: tone.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  businessDate(DateTime.now().toUtc(), _timezone),
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _timeBox('Check-in', formatTime(today?.checkInAt, _timezone))),
                    Expanded(child: _timeBox('Check-out', formatTime(today?.checkOutAt, _timezone))),
                    Expanded(
                      child: _timeBox(
                        'Duration',
                        formatDuration(today?.totalDurationSeconds),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Attendance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (today?.checkInAt == null) ...[
                  const Text(
                    'Check in when you arrive. We confirm you are inside your office geofence.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _checkIn,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryForeground,
                            ),
                          )
                        : const Text('Check in'),
                  ),
                ] else if (today?.checkOutAt == null) ...[
                  const Text(
                    'Add a short work summary when you leave.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => _submitCheckout(isUpdate: false),
                    child: const Text('Check out'),
                  ),
                ] else ...[
                  const Text(
                    'You are checked out. You can update your summary anytime.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _submitCheckout(isUpdate: true),
                    child: const Text('Update work summary'),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: const TextStyle(color: AppColors.positive, fontSize: 13)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (today?.workSummary != null) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Work summary',
              child: Text(today!.workSummary!),
            ),
          ],
          const SizedBox(height: 16),
          SectionCard(
            title: 'Assigned office',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nearestGeofence?.name ?? 'No geofence assigned',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.geofencing.isRunning
                      ? 'Automatic detection is active in the background.'
                      : 'Automatic detection is not running.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Recent location events',
            child: _events.isEmpty
                ? const Text(
                    'No events recorded yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  )
                : Column(
                    children: _events
                        .map(
                          (event) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  event.eventType,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${formatTime(event.occurredAt, _timezone)}'
                                  '${event.accuracyMeters != null ? ' · ±${event.accuracyMeters!.round()}m' : ''}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timeBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
          ),
        ),
      ],
    );
  }
}

String _describe(Object error) {
  if (error is Exception) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
  return error.toString();
}
