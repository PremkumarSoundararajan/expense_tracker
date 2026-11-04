import 'package:flutter/material.dart';

import 'spending_summary_widget.dart';

class SpendingAveragesChart extends StatelessWidget {
  const SpendingAveragesChart({
    super.key,
    required this.points,
    required this.actualAverage,
    required this.regularAverage,
    required this.currencySymbol,
    this.series = SpendSeries.regular,
  });

  final List<SpendPeriodPoint> points;
  final double actualAverage;
  final double regularAverage;
  final String currencySymbol;

  /// Which series is drawn. Only the active series (bars + average line)
  /// is rendered.
  final SpendSeries series;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Text(
        'No spending history to chart yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final isRegular = series == SpendSeries.regular;
    final seriesColor = isRegular ? colorScheme.tertiary : colorScheme.primary;
    final seriesLabel = isRegular ? 'Regular' : 'Actual';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 188,
          width: double.infinity,
          child: CustomPaint(
            painter: _AveragesChartPainter(
              points: points,
              series: series,
              average: isRegular ? regularAverage : actualAverage,
              color: seriesColor,
              gridColor: colorScheme.outlineVariant,
              labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              currencySymbol: currencySymbol,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _LegendSwatch(color: seriesColor, label: seriesLabel),
            _LegendLine(color: seriesColor, label: '$seriesLabel avg'),
          ],
        ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(16, 10),
          painter: _DashedLinePainter(color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 3.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Compact y-axis label: `$4.5k` for values of $1,000 and up, `$1.2M` for
/// millions, whole dollars from $100 to $999, and trimmed decimals below $100.
String formatChartAxisValue(double value, String currencySymbol) {
  final v = value.isFinite && value > 0 ? value : 0.0;
  String trim(double number, int digits) {
    final text = number.toStringAsFixed(digits);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  if (v >= 999950) return '$currencySymbol${trim(v / 1000000, 1)}M';
  if (v >= 999.5) return '$currencySymbol${trim(v / 1000, 1)}k';
  if (v >= 100) return '$currencySymbol${v.round()}';
  return '$currencySymbol${trim(v, 2)}';
}

class _AveragesChartPainter extends CustomPainter {
  _AveragesChartPainter({
    required this.points,
    required this.series,
    required this.average,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
    required this.currencySymbol,
  });

  final List<SpendPeriodPoint> points;
  final SpendSeries series;
  final double average;
  final Color color;
  final Color gridColor;
  final TextStyle? labelStyle;
  final String currencySymbol;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 64.0;
    const bottom = 28.0;
    const top = 8.0;
    final chartWidth = size.width - left;
    final chartHeight = size.height - bottom - top;
    if (chartWidth <= 0 || chartHeight <= 0 || points.isEmpty) return;

    final maxValue = [
      ...points.map((point) => point.valueFor(series)),
      average,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    final groupWidth = chartWidth / points.length;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = top + chartHeight * (i / 2);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);

      // Right-aligned y-axis label sitting just left of the plot area.
      final value = maxValue * (1 - i / 2);
      final axisLabel = TextPainter(
        text: TextSpan(
          text: formatChartAxisValue(value, currencySymbol),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: left - 8);
      final dy = (y - axisLabel.height / 2)
          .clamp(0.0, size.height - axisLabel.height)
          .toDouble();
      axisLabel.paint(canvas, Offset(left - 6 - axisLabel.width, dy));
    }

    if (average > 0) {
      final y = top + chartHeight * (1 - (average / maxValue).clamp(0.0, 1.0));
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.6;
      const dash = 5.0;
      var x = left;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
        x += dash * 1.8;
      }
    }

    final barPaint = Paint()..color = color;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final groupLeft = left + groupWidth * index;
      final barWidth = (groupWidth * 0.5).clamp(10.0, 32.0).toDouble();
      final barLeft = groupLeft + (groupWidth - barWidth) / 2;

      final height =
          chartHeight * (point.valueFor(series) / maxValue).clamp(0.0, 1.0);
      if (height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barLeft, top + chartHeight - height, barWidth, height),
            const Radius.circular(4),
          ),
          barPaint,
        );
      }

      final label = TextPainter(
        text: TextSpan(text: point.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: groupWidth);
      label.paint(
        canvas,
        Offset(
          groupLeft + (groupWidth - label.width) / 2,
          size.height - label.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AveragesChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.series != series ||
        oldDelegate.average != average ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.currencySymbol != currencySymbol;
  }
}
