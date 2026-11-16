import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/history_record.dart';
import '../../../../widgets/app_card.dart';
import '../../../downloads/application/download_providers.dart';
import '../../../history/application/history_controller.dart';

/// Every completed download, refreshed as downloads finish.
final completedLibraryProvider = FutureProvider<List<HistoryRecord>>((ref) async {
  ref.watch(historyRevisionProvider);
  ref.watch(tasksProvider.select((ts) => ts.where((t) => t.status.isTerminal).length));
  return ref.read(historyRepositoryProvider).query(const HistoryQuery(status: HistoryStatus.completed));
});

/// Quality buckets shown in the chart, in display order.
enum _Bucket {
  uhd('4K'),
  qhd('1440p'),
  fhd('1080p'),
  hd('720p'),
  sd('SD'),
  audio('Audio');

  const _Bucket(this.label);
  final String label;

  static _Bucket of(HistoryRecord r) {
    if (r.options.isAudioOnly || r.resolution == 'Audio') return audio;
    final p = int.tryParse(RegExp(r'(\d{3,4})').firstMatch(r.resolution ?? '')?.group(1) ?? '');
    if (p == null) return sd;
    if (p >= 2160) return uhd;
    if (p >= 1440) return qhd;
    if (p >= 1080) return fhd;
    if (p >= 720) return hd;
    return sd;
  }
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// "Library" card: monthly breakdown of completed downloads by quality, with
/// a month selector and an extruded donut chart.
class LibraryCard extends ConsumerStatefulWidget {
  const LibraryCard({super.key});

  @override
  ConsumerState<LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends ConsumerState<LibraryCard> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  List<DateTime> get _months {
    final now = DateTime.now();
    return [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month - i)];
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(completedLibraryProvider).value ?? const <HistoryRecord>[];
    final inMonth = records.where((r) => r.date.year == _month.year && r.date.month == _month.month).toList();
    // Sizes when known, otherwise file counts.
    final bySize = inMonth.any((r) => (r.fileSize ?? 0) > 0);
    final totals = <_Bucket, double>{};
    for (final r in inMonth) {
      totals.update(
        _Bucket.of(r),
        (v) => v + (bySize ? (r.fileSize ?? 0) : 1),
        ifAbsent: () => bySize ? (r.fileSize ?? 0).toDouble() : 1,
      );
    }
    final slices = [
      for (final b in _Bucket.values)
        if ((totals[b] ?? 0) > 0) _Slice(b.label, totals[b]!, AppPalette.chartColors[b.index]),
    ];
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    String fmt(double v) => bySize ? Fmt.bytes(v) : Fmt.plural(v.round(), 'file');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
      child: Builder(
        builder: (context) {
          final c = context.palette;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(
                'Library',
                trailing: Text(
                  total == 0 ? '—' : fmt(total),
                  style: context.text.titleLarge?.copyWith(fontSize: 22, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: Gap.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // keep the current month in view
                child: Row(
                  children: [
                    for (final m in _months)
                      _MonthChip(
                        label: DateFormat.MMM().format(m),
                        selected: m == _month,
                        onTap: () => setState(() => _month = m),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final legend = slices.isEmpty
                      ? Text(
                          'Nothing downloaded in ${DateFormat.MMMM().format(_month)}.',
                          style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final s in slices.take(5))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 6, right: 8),
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fmt(s.value),
                                          style: context.text.titleMedium?.copyWith(fontSize: 16, letterSpacing: -0.2),
                                        ),
                                        Text(s.label, style: context.text.bodySmall?.copyWith(color: c.textTertiary)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                  final chartSize = math.min(220.0, constraints.maxWidth * 0.55);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: legend),
                      const SizedBox(width: Gap.md),
                      SizedBox(
                        width: chartSize,
                        height: chartSize * 0.78,
                        child: Semantics(
                          label: slices.isEmpty
                              ? 'No data'
                              : slices.map((s) => '${s.label} ${fmt(s.value)}').join(', '),
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(_month),
                            tween: Tween(begin: 0, end: 1),
                            duration: Motion.slow * 2,
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => CustomPaint(
                              painter: _Donut3DPainter(slices: slices, progress: t, empty: c.surfaceHover),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? c.borderStrong : Colors.transparent),
            color: selected ? c.surface : Colors.transparent,
            boxShadow: selected ? [BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 3))] : null,
          ),
          child: Text(
            label,
            style: context.text.bodyLarge?.copyWith(
              fontSize: 15,
              color: selected ? c.textPrimary : c.textTertiary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Extruded donut seen at an angle: each slice is a ring sector whose height
/// grows with its share, slightly pulled away from the centre. Painted
/// entirely in code.
class _Donut3DPainter extends CustomPainter {
  _Donut3DPainter({required this.slices, required this.progress, required this.empty});

  final List<_Slice> slices;
  final double progress;
  final Color empty;

  static const _tilt = 0.58; // vertical squash of the ellipse
  static const _gap = 0.035; // radians between slices

  @override
  void paint(Canvas canvas, Size size) {
    final maxDepth = size.height * 0.20;
    final outer = size.width / 2 - 8;
    final inner = outer * 0.52;
    final center = Offset(size.width / 2, (size.height - maxDepth) / 2 + 4);

    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      _sector(canvas, center, inner, outer, 0, 2 * math.pi, maxDepth * 0.35, empty, 0);
      return;
    }

    // Lay slices out clockwise from 12 o'clock.
    final parts = <(double start, double sweep, _Slice s)>[];
    var a = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.value / total * 2 * math.pi * progress;
      parts.add((a, sweep, s));
      a += sweep;
    }
    // Paint back-to-front: slices whose middle is further "up" go first.
    final ordered = [...parts]..sort((x, y) => math.sin(x.$1 + x.$2 / 2).compareTo(math.sin(y.$1 + y.$2 / 2)));
    final maxShare = slices.map((s) => s.value / total).reduce(math.max);
    for (final (start, sweep, s) in ordered) {
      if (sweep <= 0) continue;
      final share = s.value / total;
      final depth = maxDepth * (0.45 + 0.55 * (share / maxShare)) * progress;
      final mid = start + sweep / 2;
      final pull = slices.length > 1 ? 5.0 : 0.0;
      final offset = Offset(math.cos(mid) * pull, math.sin(mid) * pull * _tilt);
      final g = slices.length > 1 ? _gap : 0.0;
      _sector(
        canvas,
        center + offset,
        inner,
        outer,
        start + g / 2,
        math.max(0, sweep - g),
        depth,
        s.color,
        maxDepth - depth,
      );
    }
  }

  Offset _pt(Offset c, double r, double a) => Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a) * _tilt);

  Path _face(Offset c, double ri, double ro, double start, double sweep) {
    final steps = math.max(6, (sweep / 0.05).ceil());
    final path = Path()..moveTo(_pt(c, ro, start).dx, _pt(c, ro, start).dy);
    for (var i = 1; i <= steps; i++) {
      final p = _pt(c, ro, start + sweep * i / steps);
      path.lineTo(p.dx, p.dy);
    }
    for (var i = steps; i >= 0; i--) {
      final p = _pt(c, ri, start + sweep * i / steps);
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// One extruded sector. [lift] raises shorter slices so all bases share a
  /// floor and the tall ones stand out.
  void _sector(
    Canvas canvas,
    Offset c,
    double ri,
    double ro,
    double start,
    double sweep,
    double depth,
    Color color,
    double lift,
  ) {
    final top = c.translate(0, lift);
    final hsl = HSLColor.fromColor(color);
    final side = hsl.withLightness((hsl.lightness * 0.72).clamp(0, 1)).toColor();
    final sideDark = hsl.withLightness((hsl.lightness * 0.55).clamp(0, 1)).toColor();
    final light = hsl.withLightness((hsl.lightness + 0.14).clamp(0, 1)).toColor();

    // Soft floor shadow.
    canvas.drawPath(
      _face(top.translate(0, depth + 6), ri, ro, start, sweep),
      Paint()
        ..color = const Color(0xFF1A1F6B).withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Walls: stack the face downward, darker at the bottom.
    final layers = math.max(1, depth.round());
    final face = _face(top, ri, ro, start, sweep);
    for (var i = layers; i >= 1; i--) {
      final t = i / layers;
      canvas.drawPath(face.shift(Offset(0, depth * t)), Paint()..color = Color.lerp(side, sideDark, t * 0.8)!);
    }

    // Top face with a glossy sheen.
    final bounds = face.getBounds();
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, color, color.withValues(alpha: 0.92)],
          stops: const [0, 0.55, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_Donut3DPainter old) => old.progress != progress || old.slices != slices || old.empty != empty;
}
