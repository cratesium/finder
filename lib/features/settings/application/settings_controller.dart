import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/di/providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../models/app_settings.dart';

final _log = Logger('settings');

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// Applies [change] immediately and persists it. Returns false if saving failed.
  Future<bool> change(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    final previousLevel = state.logLevel;
    state = next;
    if (next.logLevel != previousLevel) AppLogger.instance.setLevel(next.logLevel);
    try {
      await ref.read(settingsRepositoryProvider).save(next);
      return true;
    } catch (e) {
      _log.severe('settings not saved', e);
      return false;
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
