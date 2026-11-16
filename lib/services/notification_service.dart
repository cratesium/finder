import 'dart:io';
import 'dart:ui' show Color;

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

/// Native notifications (Notification Center / Windows toast / Android /
/// iOS / Linux desktop notifications via D-Bus).
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
        appUserModelId: 'Cratesium.Finder.Desktop.1',
        guid: '6d6f9c3e-6a55-4b8e-9b62-5f1f7f0c2a41',
      );
      // Monochrome brand glyph (Android requires a white-on-transparent small icon).
      const android = AndroidInitializationSettings('@drawable/ic_stat_finder');
      const linux = LinuxInitializationSettings(defaultActionName: 'Open');
      const settings = InitializationSettings(
        macOS: darwin,
        iOS: darwin,
        windows: windows,
        android: android,
        linux: linux,
      );
      final ok = await _plugin.initialize(settings: settings);
      if (Platform.isAndroid) {
        // Android 13+ asks the user before an app may post notifications.
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      return ok ?? false;
    } catch (e) {
      _log.info('notifications unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> show({required String title, required String body}) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isAndroid || Platform.isIOS || Platform.isLinux)) {
      return;
    }
    final ready = await (_ready ??= _init());
    if (!ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(),
          iOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
          linux: LinuxNotificationDetails(),
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'Download completed or failed',
            importance: Importance.defaultImportance,
            icon: '@drawable/ic_stat_finder',
            color: Color(0xFF0A0A0A), // monochrome brand
          ),
        ),
      );
    } catch (e) {
      _log.info('failed to show notification: $e');
    }
  }
}
