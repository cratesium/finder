import 'package:intl/intl.dart';

/// Human-readable formatting helpers.
abstract final class Fmt {
  static const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  static String bytes(num? value, {int decimals = 1}) {
    if (value == null || value < 0) return '—';
    var v = value.toDouble();
    var i = 0;
    while (v >= 1024 && i < _units.length - 1) {
      v /= 1024;
      i++;
    }
    final d = i == 0 ? 0 : decimals;
    return '${v.toStringAsFixed(d)} ${_units[i]}';
  }

  static String speed(num? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return '—';
    return '${bytes(bytesPerSecond)}/s';
  }

  /// Formats a duration as `h:mm:ss` or `m:ss`.
  static String duration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  /// Longer form for totals: `3 h 12 min`.
  static String durationLong(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  static String eta(int? seconds) {
    if (seconds == null || seconds < 0) return '—';
    return '${duration(Duration(seconds: seconds))} left';
  }

  static String dateTime(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('d MMM y, HH:mm').format(t.toLocal());
  }

  static String date(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('d MMM y').format(t.toLocal());
  }

  static String percent(double? fraction) {
    if (fraction == null) return '—';
    return '${(fraction * 100).clamp(0, 100).toStringAsFixed(1)}%';
  }

  static String plural(int count, String singular, [String? pluralForm]) =>
      '$count ${count == 1 ? singular : (pluralForm ?? '${singular}s')}';
}
