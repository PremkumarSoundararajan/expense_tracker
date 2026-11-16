import 'package:flutter/material.dart';

class AppLinearProgressIndicator extends StatelessWidget {
  const AppLinearProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.trackColor,
  });

  final double? value;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LinearProgressIndicator(
      value: value,
      minHeight: 10,
      borderRadius: BorderRadius.circular(999),
      color: color ?? colors.primary,
      backgroundColor: trackColor ?? colors.primaryContainer,
    );
  }
}
