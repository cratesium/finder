import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/errors/app_error.dart';

final _log = Logger('installer');

typedef InstallProgress = void Function(double? fraction, String stage);

/// Downloads release assets over HTTPS and verifies them against the SHA-256
/// checksum list published in the same official release.
class BinaryInstaller {
  BinaryInstaller({
    HttpClient Function()? clientFactory,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final int maxAttempts;
  final Duration retryDelay;

  /// Maximum time without receiving any data. A silently dead connection would
  /// otherwise hang forever, since HttpClient has no body read timeout.
  final Duration idleTimeout;

  HttpClient _client() => _clientFactory()..connectionTimeout = idleTimeout;

  /// Parses `sha256sum`-style files: `<hex>  <name>` or `<hex> *<name>`.
  static Map<String, String> parseChecksums(String text) {
    final out = <String, String>{};
    for (final raw in const LineSplitter().convert(text)) {
      final m = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(raw.trim());
      if (m != null) out[m.group(2)!.trim()] = m.group(1)!.toLowerCase();
    }
    return out;
  }

  Future<String> fetchText(Uri url) async {
    final client = _client();
    try {
      final req = await client.getUrl(url);
      final res = await req.close().timeout(idleTimeout);
      if (res.statusCode != 200) {
        throw AppError(AppErrorKind.network,
            'Couldn\'t download the checksum list (HTTP ${res.statusCode}).');
      }
      return await res.timeout(idleTimeout).transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw AppError.of(AppErrorKind.network, detail: e.message);
    } on TimeoutException {
      throw AppError.of(AppErrorKind.network, detail: 'no data received for ${idleTimeout.inSeconds}s');
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [url] to [target] only if its SHA-256 equals [expectedSha256].
  Future<File> downloadVerified({
    required Uri url,
    required String expectedSha256,
    required File target,
    InstallProgress? onProgress,
  }) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.download');
    final client = _client();
    try {
      _log.info('downloading ${url.path.split('/').last}');
      final req = await client.getUrl(url);
      final res = await req.close().timeout(idleTimeout);
      if (res.statusCode != 200) {
        throw AppError(AppErrorKind.network, 'Download failed (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength > 0 ? res.contentLength : null;
      final sink = tmp.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in res.timeout(idleTimeout)) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress?.call(total == null ? null : received / total, 'Downloading');
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      final actual = digestSink.value.toString();
      if (actual != expectedSha256.toLowerCase()) {
        await tmp.delete();
        _log.severe('checksum mismatch for ${url.path}: expected $expectedSha256 got $actual');
        throw const AppError(AppErrorKind.unknown,
            'The downloaded file failed checksum verification and was discarded.');
      }
      onProgress?.call(1, 'Verified');
      if (await target.exists()) await target.delete();
      return await tmp.rename(target.path);
    } on SocketException catch (e) {
      throw AppError.of(AppErrorKind.network, detail: e.message);
    } on HttpException catch (e) {
      throw AppError.of(AppErrorKind.network, detail: e.message);
    } on TimeoutException {
      throw AppError.of(AppErrorKind.network, detail: 'download stalled for ${idleTimeout.inSeconds}s');
    } finally {
      client.close(force: true);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// Downloads an asset listed in [checksumsUrl] and verifies it.
  ///
  /// Network failures (drops, stalls) are retried a few times; checksum
  /// failures never are.
  Future<File> installAsset({
    required String releaseBase,
    required Uri checksumsUrl,
    required String assetName,
    required File target,
    InstallProgress? onProgress,
  }) async {
    onProgress?.call(null, 'Fetching checksums');
    final sums = parseChecksums(await _withRetries(() => fetchText(checksumsUrl), onProgress));
    final expected = sums[assetName];
    if (expected == null) {
      throw AppError(AppErrorKind.unknown,
          'The official release doesn\'t list a checksum for $assetName, so it wasn\'t installed.');
    }
    return _withRetries(
      () => downloadVerified(
        url: Uri.parse('$releaseBase/$assetName'),
        expectedSha256: expected,
        target: target,
        onProgress: onProgress,
      ),
      onProgress,
    );
  }

  Future<T> _withRetries<T>(Future<T> Function() op, InstallProgress? onProgress) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await op();
      } on AppError catch (e) {
        if (e.kind != AppErrorKind.network || attempt >= maxAttempts) rethrow;
        _log.info('attempt $attempt failed (${e.detail}); retrying');
        onProgress?.call(null, 'Retrying ($attempt/${maxAttempts - 1})');
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }

  /// Extracts a zip archive using the OS-provided `tar` (bsdtar), which ships
  /// with Windows 10+ and macOS. Arguments are passed without a shell.
  static Future<void> extractZip(File archive, Directory into) async {
    await into.create(recursive: true);
    final tar = Platform.isWindows
        ? p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32', 'tar.exe')
        : '/usr/bin/tar';
    final r = await Process.run(tar, ['-xf', archive.path, '-C', into.path], runInShell: false);
    if (r.exitCode != 0) {
      throw AppError(AppErrorKind.unknown, 'Couldn\'t extract the downloaded archive.',
          detail: '${r.stderr}');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
