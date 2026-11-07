import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';

import '../core/config/app_config.dart';

final _log = Logger('notifications');

abstract interface class NotificationService {
  Future<void> show({required String title, required String body});
}

class NoopNotificationService implements NotificationService {
  const NoopNotificationService();
  @override
  Future<void> show({required String title, required String body}) async {}
}

/// Native desktop notifications (Notification Center / Windows toast).
///
/// Initialization is lazy and failures are logged and ignored, so missing
/// notification permissions never affect downloads.
class DesktopNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  int _nextId = 1;

  Future<bool> _init() async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const windows = WindowsInitializationSettings(
        appName: AppConfig.appName,
        appUserModelId: 'CourseGrab.CourseGrab.Desktop.1',
        guid: '6d6f9c3e-6a55-4b8e-9b62-5f1f7f0c2a41',
      );
      const settings = InitializationSettings(macOS: darwin, windows: windows);
      final ok = await _plugin.initialize(settings: settings);
      return ok ?? false;
    } catch (e) {
      _log.info('notifications unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> show({required String title, required String body}) async {
    if (!(Platform.isMacOS || Platform.isWindows)) return;
    final ready = await (_ready ??= _init());
    if (!ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      _log.info('failed to show notification: $e');
    }
  }
}
