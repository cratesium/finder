import 'package:flutter/services.dart';

/// Joins separate video and audio files into one MP4 without re-encoding.
abstract interface class Muxer {
  /// Returns the short-side resolution of the result, when known.
  Future<int?> mux({required String videoPath, required String audioPath, required String outputPath});
}

/// Keeps work running briefly after the app moves to the background.
abstract interface class BackgroundTasks {
  Future<int?> begin(String name);
  Future<void> end(int? id);
}

/// `finder/ios` channel implemented in ios/Runner/FinderIosPlugin.swift.
class IosBridge implements Muxer, BackgroundTasks {
  const IosBridge([this._channel = const MethodChannel('finder/ios')]);
  final MethodChannel _channel;

  /// AVFoundation passthrough export (AVMutableComposition → MP4).
  @override
  Future<int?> mux({required String videoPath, required String audioPath, required String outputPath}) =>
      _channel.invokeMethod<int>('mux', {'video': videoPath, 'audio': audioPath, 'output': outputPath});

  /// `UIApplication.beginBackgroundTask`; returns the task identifier.
  @override
  Future<int?> begin(String name) async {
    try {
      return await _channel.invokeMethod<int>('beginBackgroundTask', {'name': name});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> end(int? id) async {
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('endBackgroundTask', {'id': id});
    } on PlatformException {
      // Already expired.
    }
  }

  /// Quick Look preview of a downloaded file.
  Future<void> preview(String path) => _channel.invokeMethod<void>('preview', {'path': path});

  /// Share sheet (save to Photos, AirDrop, other apps).
  Future<void> share(String path) => _channel.invokeMethod<void>('share', {'path': path});

  /// Opens the Files app at [dir] (inside "On My iPhone/iPad → Finder").
  /// Returns false when Files couldn't be opened.
  Future<bool> openInFiles(String dir) async =>
      await _channel.invokeMethod<bool>('openInFiles', {'path': dir}) ?? false;
}
