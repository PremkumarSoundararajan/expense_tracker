import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/classified_spending_breakdown_service.dart';
import '../utils/currency_format.dart';

enum _Dimension { essentiality, category }

class SpendingBreakdown extends StatefulWidget {
  const SpendingBreakdown({
    super.key,
    required this.data,
    required this.currencySymbol,
    this.onReviewMerchants,
  });
  final ClassifiedSpendingBreakdown data;
  final String currencySymbol;
  final VoidCallback? onReviewMerchants;
  @override
  State<SpendingBreakdown> createState() => _SpendingBreakdownState();
}

class _SpendingBreakdownState extends State<SpendingBreakdown> {
  _Dimension _dimension = _Dimension.essentiality;
  String money(double amount) =>
      formatFullCurrency(amount, widget.currencySymbol);
  // Stable text hash keeps category colors stable across sorting and updates.
  Color color(String name) {
    if (name == 'Essential') return const Color(0xFF288B70);
    if (name == 'Potentially Flexible') return const Color(0xFFE58B29);
    const palette = [
      Color(0xFF4A9ED3),
      Color(0xFFB48CDD),
      Color(0xFFE58B29),
      Color(0xFF288B70),
      Color(0xFFDE7994),
      Color(0xFF9BA647),
      Color(0xFF45ADAD),
    ];
    final hash = name.codeUnits.fold<int>(
      0,
      (sum, unit) => (sum * 31 + unit) & 0x7fffffff,
    );
    return palette[hash % palette.length];
  }

  Widget label(
    SpendingBreakdownItem item,
    ClassifiedSpendingDimension data, {
    bool bar = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Icon(Icons.circle, size: 10, color: color(item.name)),
            ),
            Expanded(child: Text(item.name)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            '${money(item.amount)} · ${data.percent(item).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (bar)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 18),
            child: LinearProgressIndicator(
              value: data.classifiedTotal <= 0
                  ? 0
                  : (item.amount.abs() /
                            data.items.fold<double>(
                              0,
                              (sum, i) => sum + i.amount.abs(),
                            ))
                        .clamp(0, 1),
              color: color(item.name),
              minHeight: 7,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
      ],
    ),
  );

  Future<void> fullCategories(ClassifiedSpendingDimension data) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('All categories'),
          content: SizedBox(
            width: 480,
            height: 400,
            child: ListView.builder(
              itemCount: data.items.length,
              itemBuilder: (_, index) =>
                  label(data.items[index], data, bar: true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final essential = _dimension == _Dimension.essentiality;
    final data = essential ? widget.data.essentiality : widget.data.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_Dimension>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _Dimension.essentiality,
              label: Text('Essentiality'),
            ),
            ButtonSegment(value: _Dimension.category, label: Text('Category')),
          ],
          selected: {_dimension},
          onSelectionChanged: (value) =>
              setState(() => _dimension = value.first),
        ),
        const SizedBox(height: 8),
        Text(
          '${essential ? 'Essentiality' : 'Categories'} classified: ${data.coverage.toStringAsFixed(1)}% of spending',
          key: const ValueKey('breakdown-coverage'),
        ),
        Text(
          'All recorded eligible history · totals, not monthly averages',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (data.items.isEmpty || data.classifiedTotal <= 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No classified spending to display yet.'),
          )
        else ...[
          const SizedBox(height: 8),
          if (essential)
            LayoutBuilder(
              builder: (_, constraints) {
                final negative = data.items.any((i) => i.amount < 0);
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final item in data.items) label(item, data)],
                );
                final chart = Semantics(
                  label:
                      'Essentiality spending donut. ${data.items.map((i) => '${i.name}: ${money(i.amount)}, ${data.percent(i).toStringAsFixed(1)} percent').join('. ')}',
                  child: SizedBox(
                    width: 144,
                    height: 144,
                    child: CustomPaint(
                      key: const ValueKey('essentiality-donut'),
                      painter: _DonutPainter(
                        data.items
                            .map((i) => (i.amount, color(i.name)))
                            .toList(),
                      ),
                    ),
                  ),
                );
                if (negative) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Refund adjustments exceed spending in a group. Net amounts are shown below.',
                      ),
                      legend,
                    ],
                  );
                }
                return constraints.maxWidth < 480
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: InkWell(
                              onTap: widget.onReviewMerchants,
                              child: chart,
                            ),
                          ),
                          legend,
                        ],
                      )
                    : Row(
                        children: [
                          InkWell(
                            onTap: widget.onReviewMerchants,
                            child: chart,
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: legend),
                        ],
                      );
              },
            )
          else ...[
            for (final item in data.topCategories)
              InkWell(
                onTap: widget.onReviewMerchants,
                child: label(item, data, bar: true),
              ),
            TextButton(
              onPressed: () => fullCategories(data),
              child: Text('View all categories (${data.items.length})'),
            ),
          ],
          if (data.coverage < 99.95 && data.coverage >= 0)
            Text(
              'Only spending classified for this dimension is shown.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (data.coverage < 0 ||
              data.coverage > 100 ||
              data.items.any((i) => i.amount < 0))
            Text(
              'Net amounts include refunds; percentages can fall outside 0–100%.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        if (widget.onReviewMerchants != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('review-classified-merchants'),
            onPressed: widget.onReviewMerchants,
            icon: const Icon(Icons.table_rows_outlined),
            label: const Text('Review classified merchants'),
          ),
        ],
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.slices);
  final List<(double, Color)> slices;
  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.$1);
    if (total <= 0) return;
    final rect = (Offset.zero & size).deflate(13);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.$1 / total * math.pi * 2;
      paint.color = slice.$2;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}
