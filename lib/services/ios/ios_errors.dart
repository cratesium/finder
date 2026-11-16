import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/errors/app_error.dart';

/// Maps youtube_explode / IO / platform failures to user-safe [AppError]s.
abstract final class IosErrors {
  static AppError map(Object e) {
    if (e is AppError) return e;
    if (e is yt.VideoRequiresPurchaseException) {
      return AppError.of(AppErrorKind.inaccessible, detail: '$e');
    }
    if (e is yt.VideoUnavailableException) {
      return AppError.of(AppErrorKind.unavailable, detail: '$e');
    }
    if (e is yt.VideoUnplayableException) {
      return AppError.of(AppErrorKind.inaccessible, detail: '$e');
    }
    if (e is yt.RequestLimitExceededException) {
      return AppError(
        AppErrorKind.network,
        'YouTube is limiting requests right now. Try again in a few minutes.',
        detail: '$e',
      );
    }
    if (e is yt.YoutubeExplodeException) {
      return AppError(AppErrorKind.unavailable, 'YouTube didn\'t return this video\'s information.', detail: '$e');
    }
    if (e is SocketException || e is HttpException || e is HandshakeException) {
      if (e is HandshakeException) return AppError.of(AppErrorKind.certificate, detail: '$e');
      return AppError.of(AppErrorKind.network, detail: '$e');
    }
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      // ENOSPC (28) on iOS/Darwin.
      if (code == 28) return AppError.of(AppErrorKind.diskFull, detail: e.message);
      if (code == 13 || code == 1) return AppError.of(AppErrorKind.permission, detail: e.message);
      return AppError.of(AppErrorKind.storage, detail: '${e.message} (${e.osError})');
    }
    if (e is PlatformException) {
      return AppError(
        AppErrorKind.ffmpeg,
        'Finder couldn\'t combine the video and audio on this device.',
        detail: '${e.code}: ${e.message}',
      );
    }
    return AppError.of(AppErrorKind.unknown, detail: '$e');
  }
}
