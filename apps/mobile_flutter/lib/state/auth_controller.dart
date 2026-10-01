import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/api.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._api);

  final Api _api;
  StreamSubscription<AuthState>? _subscription;

  Session? _session;
  UserProfile? _profile;
  bool _loading = true;

  Session? get session => _session;
  UserProfile? get profile => _profile;
  bool get loading => _loading;
  bool get isSignedIn => _session != null;

  Future<void> init() async {
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    await _loadProfile();
    _subscription = auth.onAuthStateChange.listen((state) async {
      _session = state.session;
      await _loadProfile();
      notifyListeners();
    });
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final userId = _session?.user.id;
    if (userId == null) {
      _profile = null;
      return;
    }
    try {
      _profile = await _api.fetchProfile(userId);
    } catch (_) {
      _profile = null;
    }
  }

  /// Re-reads the profile (e.g. after toggling attendance tracking).
  Future<void> refreshProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
