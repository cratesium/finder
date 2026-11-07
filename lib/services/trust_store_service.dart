import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/utils/platform_info.dart';

final _log = Logger('trust');

/// Network configuration applied to every yt-dlp invocation.
///
/// yt-dlp bundles Mozilla's CA list (certifi). On networks that inspect TLS
/// with an organization CA installed in the OS (common on managed computers)
/// that list fails with `CERTIFICATE_VERIFY_FAILED`. With system certificates
/// enabled, yt-dlp trusts exactly what the operating system trusts. Certificate
/// verification is never disabled.
class YtDlpNetworkConfig {
  const YtDlpNetworkConfig({this.useSystemCertificates = false, this.caBundlePath});

  static const none = YtDlpNetworkConfig();

  final bool useSystemCertificates;

  /// PEM bundle exported from the OS trust store (macOS). Windows doesn't need
  /// one because Python reads the Windows certificate store directly.
  final String? caBundlePath;

  List<String> get arguments => useSystemCertificates ? const ['--compat-options', 'no-certifi'] : const [];

  Map<String, String> get environment =>
      useSystemCertificates && caBundlePath != null ? {'SSL_CERT_FILE': caBundlePath!} : const {};
}

/// Builds [YtDlpNetworkConfig] from the host trust store.
class TrustStoreService {
  TrustStoreService({required this.platform, required this.dataDir});

  final PlatformInfo platform;
  final String dataDir;

  static const _macKeychains = [
    '/System/Library/Keychains/SystemRootCertificates.keychain',
    '/Library/Keychains/System.keychain',
  ];

  Future<YtDlpNetworkConfig> build({required bool useSystemCertificates}) async {
    if (!useSystemCertificates) return YtDlpNetworkConfig.none;
    if (platform.isWindows) return const YtDlpNetworkConfig(useSystemCertificates: true);
    if (!platform.isMacOS) return YtDlpNetworkConfig.none;

    final pem = await exportMacRoots();
    // Without a bundle, disabling certifi would leave Python with no CAs, so
    // fall back to yt-dlp's defaults instead of breaking every connection.
    if (pem == null) return YtDlpNetworkConfig.none;
    return YtDlpNetworkConfig(useSystemCertificates: true, caBundlePath: pem);
  }

  /// Exports trusted roots from the macOS keychains to a PEM file.
  Future<String?> exportMacRoots() async {
    final keychains = [
      for (final k in _macKeychains)
        if (await File(k).exists()) k,
    ];
    if (keychains.isEmpty) return null;
    try {
      final r = await Process.run(
        '/usr/bin/security',
        ['find-certificate', '-a', '-p', ...keychains],
        runInShell: false,
      );
      final pem = r.stdout is String ? r.stdout as String : '';
      final count = 'BEGIN CERTIFICATE'.allMatches(pem).length;
      if (r.exitCode != 0 || count == 0) {
        _log.warning('keychain export failed (exit ${r.exitCode})');
        return null;
      }
      final dir = Directory(p.join(dataDir, 'certs'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'system-roots.pem'));
      await file.writeAsString(pem, flush: true);
      _log.info('exported $count system certificates for yt-dlp');
      return file.path;
    } catch (e) {
      _log.warning('keychain export failed', e);
      return null;
    }
  }
}
