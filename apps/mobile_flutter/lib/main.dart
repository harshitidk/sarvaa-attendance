import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'services/admin_api.dart';
import 'services/api.dart';
import 'services/geofencing_service.dart';
import 'services/notification_service.dart';
import 'state/auth_controller.dart';
import 'state/theme_controller.dart';
import 'utils/attendance_logic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeTimezones();
  // Before any UI: restoring this later would flash the light theme first.
  final theme = await ThemeController.load();
  await NotificationService.init();

  if (!AppConfig.isConfigured) {
    runApp(ConfigMissingApp(theme: theme));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  final api = Api(Supabase.instance.client);
  final adminApi = AdminApi(Supabase.instance.client);
  final auth = AuthController(api);
  final geofencing = GeofencingService(api);
  await auth.init();

  runApp(GeoAttendApp(
    api: api,
    adminApi: adminApi,
    auth: auth,
    geofencing: geofencing,
    theme: theme,
  ));
}
