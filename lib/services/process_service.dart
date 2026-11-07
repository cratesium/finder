import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import '../core/config/app_config.dart';

final _log = Logger('process');

/// Outcome of a short-lived process run via [ProcessService.run].
class ProcessOutcome {
  const ProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;
}

/// A running child process with line-oriented output streams.
class ManagedProcess {
  ManagedProcess._(this._service, this._process, this.executable)
      : stdoutLines = _process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .asBroadcastStream(),
        stderrLines = _process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .asBroadcastStream();

  final ProcessService _service;
  final Process _process;
  final String executable;
  final Stream<String> stdoutLines;
  final Stream<String> stderrLines;
  bool _terminating = false;

  int get pid => _process.pid;
  Future<int> get exitCode => _process.exitCode;
  bool get isTerminating => _terminating;

  /// Stops the process and its descendants.
  ///
  /// A polite interrupt is sent first so yt-dlp can stop FFmpeg and keep its
  /// partial-download state; after [grace] the whole tree is killed.
  Future<void> terminate({Duration grace = AppConfig.processKillGrace}) async {
    if (_terminating) {
      await exitCode.timeout(grace * 2, onTimeout: () => -1);
      return;
    }
    _terminating = true;
    await _service.terminateTree(_process, grace: grace);
  }
}

/// Starts native processes safely.
///
/// * Executables and arguments are always passed separately and never through
///   a shell, so URLs and paths cannot be interpreted as shell syntax.
/// * Every started process is tracked so it can be cleaned up on shutdown.
class ProcessService {
  ProcessService({this.isWindows = false});

  factory ProcessService.forHost() => ProcessService(isWindows: Platform.isWindows);

  final bool isWindows;
  final Map<int, Process> _live = {};

  int get liveCount => _live.length;

  Map<String, String> _environment(Map<String, String>? extra) => {
        // Force UTF-8 output from Python-based tools (yt-dlp) on every OS.
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        'PYTHONUNBUFFERED': '1',
        ...?extra,
      };

  /// Starts a long-running process.
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    _log.fine('start $executable ${arguments.length} args');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environment(environment),
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    _live[process.pid] = process;
    unawaited(process.exitCode.then((code) {
      _live.remove(process.pid);
      _log.fine('pid ${process.pid} exited with $code');
    }));
    return ManagedProcess._(this, process, executable);
  }

  /// Runs a process to completion, collecting output, with a timeout.
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = AppConfig.probeTimeout,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final proc = await start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = proc.stdoutLines.forEach(out.writeln);
    final errDone = proc.stderrLines.forEach(err.writeln);
    var timedOut = false;
    final code = await proc.exitCode.timeout(timeout, onTimeout: () async {
      timedOut = true;
      await proc.terminate(grace: const Duration(seconds: 1));
      return -1;
    });
    await Future.wait([outDone, errDone]).timeout(
      const Duration(seconds: 2),
      onTimeout: () => const [],
    );
    return ProcessOutcome(
      exitCode: code,
      stdout: out.toString(),
      stderr: err.toString(),
      timedOut: timedOut,
    );
  }

  /// Terminates [process] and any child processes it spawned.
  Future<void> terminateTree(Process process, {required Duration grace}) async {
    final pid = process.pid;
    if (isWindows) {
      // taskkill /T kills the whole tree (yt-dlp + ffmpeg children).
      try {
        await Process.run('taskkill', ['/PID', '$pid', '/T', '/F'], runInShell: false);
      } catch (e) {
        _log.warning('taskkill failed for $pid', e);
      }
      process.kill();
      await process.exitCode.timeout(grace, onTimeout: () => -1);
      return;
    }

    // POSIX: SIGINT lets yt-dlp shut down FFmpeg and keep .part files.
    final descendants = await _descendants(pid);
    process.kill(ProcessSignal.sigint);
    final exited = await process.exitCode
        .then((_) => true)
        .timeout(grace, onTimeout: () => false);
    if (!exited) {
      _log.info('pid $pid did not exit after SIGINT; sending SIGKILL');
      process.kill(ProcessSignal.sigkill);
    }
    // Make sure no grandchildren (e.g. ffmpeg) survive.
    final remaining = {...descendants, ...await _descendants(pid)};
    for (final child in remaining) {
      Process.killPid(child, ProcessSignal.sigkill);
    }
    await process.exitCode.timeout(grace, onTimeout: () => -1);
  }

  Future<Set<int>> _descendants(int pid) async {
    final result = <int>{};
    final queue = [pid];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      try {
        final r = await Process.run('pgrep', ['-P', '$current'], runInShell: false);
        for (final line in (r.stdout as String).split('\n')) {
          final child = int.tryParse(line.trim());
          if (child != null && result.add(child)) queue.add(child);
        }
      } catch (_) {
        break;
      }
    }
    return result;
  }

  /// Terminates every live child process. Called on application shutdown.
  Future<void> killAll({Duration grace = const Duration(seconds: 2)}) async {
    final procs = _live.values.toList();
    if (procs.isEmpty) return;
    _log.info('terminating ${procs.length} child process(es)');
    await Future.wait(procs.map((p) => terminateTree(p, grace: grace)));
    _live.clear();
  }
}
