import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// Charts are hand-painted rather than pulled from a charting package. The app
/// needs exactly three shapes, they have to match the theme in both
/// brightnesses, and a CustomPainter has no version churn to manage.

class ChartBar {
  const ChartBar({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.secondaryValue,
  });

  final String label;

  /// Centavos.
  final int value;

  /// Drawn as a darker inner bar -- used to show profit sitting inside revenue.
  final int? secondaryValue;

  /// The bar that represents "now": today in a week view, this month in a
  /// year view. Painted in the accent so the eye lands on it first.
  final bool emphasized;
}

/// A vertical bar chart with a value axis, zero-filled gaps, and an optional
/// selected column. Tapping a bar reports its index.
class BarChartView extends StatelessWidget {
  const BarChartView({
    super.key,
    required this.bars,
    this.height = 180,
    this.selectedIndex,
    this.onSelect,
    this.showAxis = true,
    this.maxLabelEvery = 1,
  });

  final List<ChartBar> bars;
  final double height;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;
  final bool showAxis;

  /// Draw every Nth x-axis label. Month views set this to 3 or so, otherwise
  /// 31 labels collide into an unreadable smear.
  final int maxLabelEvery;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data yet',
            style: TextStyle(color: context.colors.muted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSelect == null
              ? null
              : (details) {
                  final axisWidth = showAxis ? _BarChartPainter.axisWidth : 0.0;
                  final plotWidth = width - axisWidth;
                  if (plotWidth <= 0) return;
                  final x = details.localPosition.dx - axisWidth;
                  final index = (x / plotWidth * bars.length).floor();
                  if (index >= 0 && index < bars.length) onSelect!(index);
                },
          child: SizedBox(
            height: height,
            width: width,
            child: CustomPaint(
              painter: _BarChartPainter(
                bars: bars,
                selectedIndex: selectedIndex,
                showAxis: showAxis,
                labelEvery: maxLabelEvery,
                barColor: context.scheme.primary,
                emphasisColor: context.colors.accent,
                innerColor: context.colors.good,
                gridColor: context.colors.chartGrid,
                labelColor: context.colors.muted,
                selectedColor: context.scheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.bars,
    required this.selectedIndex,
    required this.showAxis,
    required this.labelEvery,
    required this.barColor,
    required this.emphasisColor,
    required this.innerColor,
    required this.gridColor,
    required this.labelColor,
    required this.selectedColor,
  });

  static const double axisWidth = 44;
  static const double labelHeight = 20;

  final List<ChartBar> bars;
  final int? selectedIndex;
  final bool showAxis;
  final int labelEvery;
  final Color barColor;
  final Color emphasisColor;
  final Color innerColor;
  final Color gridColor;
  final Color labelColor;
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final left = showAxis ? axisWidth : 0.0;
    final plot = Rect.fromLTWH(
      left,
      6,
      size.width - left,
      size.height - labelHeight - 6,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final rawMax = bars.fold<int>(0, (m, b) => math.max(m, b.value));
    // A flat-zero chart still needs a sensible axis, and rounding the top up to
    // a round peso figure keeps the gridline labels readable.
    final maxValue = rawMax == 0 ? 10000 : _niceCeiling(rawMax);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 2; i++) {
      final t = i / 2;
      final y = plot.bottom - plot.height * t;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);

      if (showAxis) {
        _paintText(
          canvas,
          Money.formatShort((maxValue * t).round()),
          Offset(axisWidth - 6, y),
          color: labelColor,
          fontSize: 10,
          align: TextAlign.right,
          anchorRight: true,
          anchorMiddle: true,
          maxWidth: axisWidth - 8,
        );
      }
    }

    final slot = plot.width / bars.length;
    final barWidth = math.min(slot * 0.62, 34.0);

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final centerX = plot.left + slot * i + slot / 2;
      final isSelected = selectedIndex == i;

      final barHeight = maxValue == 0
          ? 0.0
          : (bar.value / maxValue * plot.height).clamp(0.0, plot.height);

      if (isSelected) {
        canvas.drawRect(
          Rect.fromLTWH(plot.left + slot * i, plot.top, slot, plot.height),
          Paint()..color = selectedColor.withValues(alpha: 0.06),
        );
      }

      // Zero days still get a visible sliver, so the row reads as "nothing
      // sold" rather than as a gap in the data.
      final drawnHeight = bar.value == 0 ? 2.0 : math.max(barHeight, 2.0);
      final rect = Rect.fromLTWH(
        centerX - barWidth / 2,
        plot.bottom - drawnHeight,
        barWidth,
        drawnHeight,
      );

      final color = bar.emphasized ? emphasisColor : barColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()
          ..color = bar.value == 0 ? gridColor : color.withValues(alpha: 0.9),
      );

      final secondary = bar.secondaryValue;
      if (secondary != null && secondary > 0 && maxValue > 0) {
        final innerHeight =
            (secondary / maxValue * plot.height).clamp(0.0, drawnHeight);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(
              centerX - barWidth / 2,
              plot.bottom - innerHeight,
              barWidth,
              innerHeight,
            ),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = innerColor.withValues(alpha: 0.85),
        );
      }

      final showLabel = i % labelEvery == 0 || isSelected;
      if (showLabel) {
        _paintText(
          canvas,
          bar.label,
          Offset(centerX, size.height - labelHeight / 2 - 2),
          color: isSelected ? selectedColor : labelColor,
          fontSize: 10,
          weight: isSelected ? FontWeight.w700 : FontWeight.w500,
          anchorCenter: true,
          anchorMiddle: true,
          maxWidth: slot + 8,
        );
      }
    }

    // Baseline last, so it sits on top of the bars.
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1.5,
    );
  }

  /// Rounds a peso amount up to a clean axis top: 1/2/5 times a power of ten.
  int _niceCeiling(int value) {
    if (value <= 0) return 10000;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
    final normalized = value / magnitude;
    final step = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;
    return (step * magnitude).round();
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.bars != bars ||
      old.selectedIndex != selectedIndex ||
      old.barColor != barColor;
}

/// A single horizontal bar split into proportional segments. Used for the
/// cash / utang / GCash mix, where a pie would be harder to read at this size.
class ProportionSlice {
  const ProportionSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class ProportionBar extends StatelessWidget {
  const ProportionBar({
    super.key,
    required this.slices,
    this.height = 14,
    this.showLegend = true,
  });

  final List<ProportionSlice> slices;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: total == 0
                ? ColoredBox(color: context.colors.chartGrid)
                : Row(
                    children: [
                      for (final slice in slices)
                        if (slice.value > 0)
                          Expanded(
                            flex: slice.value,
                            child: ColoredBox(color: slice.color),
                          ),
                    ],
                  ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final slice in slices)
                _LegendEntry(
                  slice: slice,
                  share: total == 0 ? 0 : slice.value / total,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.slice, required this.share});

  final ProportionSlice slice;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          slice.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.scheme.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          Money.formatShort(slice.value),
          style: TextStyle(
            fontSize: 12.5,
            color: context.colors.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (share > 0) ...[
          const SizedBox(width: 4),
          Text(
            '(${(share * 100).round()}%)',
            style: TextStyle(fontSize: 11.5, color: context.colors.muted),
          ),
        ],
      ],
    );
  }
}

/// A ranked list where each row carries a proportional fill behind it -- the
/// bar and the number occupy the same space instead of needing a separate
/// chart beside the table.
class RankedBarList extends StatelessWidget {
  const RankedBarList({
    super.key,
    required this.rows,
    this.emptyMessage = 'No data yet',
  });

  final List<RankedBarRow> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            emptyMessage,
            style: TextStyle(color: context.colors.muted),
          ),
        ),
      );
    }

    final max = rows.fold<int>(0, (m, r) => math.max(m, r.value));

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _RankedRow(row: row, max: max),
          ),
      ],
    );
  }
}

class RankedBarRow {
  const RankedBarRow({
    required this.label,
    required this.value,
    this.trailing,
    this.color,
  });

  final String label;
  final int value;
  final String? trailing;
  final Color? color;
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.row, required this.max});

  final RankedBarRow row;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fill = max == 0 ? 0.0 : (row.value / max).clamp(0.0, 1.0);
    final color = row.color ?? context.scheme.primary;

    return Stack(
      children: [
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fill == 0 ? 0.004 : fill,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (row.trailing != null) ...[
                Text(
                  row.trailing!,
                  style: TextStyle(fontSize: 12.5, color: context.colors.muted),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                Money.format(row.value),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _paintText(
  Canvas canvas,
  String text,
  Offset position, {
  required Color color,
  double fontSize = 11,
  FontWeight weight = FontWeight.w500,
  TextAlign align = TextAlign.left,
  bool anchorCenter = false,
  bool anchorRight = false,
  bool anchorMiddle = false,
  double maxWidth = 200,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '',
  )..layout(maxWidth: maxWidth);

  var dx = position.dx;
  if (anchorCenter) dx -= painter.width / 2;
  if (anchorRight) dx -= painter.width;

  final dy = anchorMiddle ? position.dy - painter.height / 2 : position.dy;
  painter.paint(canvas, Offset(dx, dy));
}
