import 'package:flutter/material.dart';

import '../app_theme.dart';

class AccentIconChip extends StatelessWidget {
  const AccentIconChip({
    super.key,
    required this.icon,
    required this.accent,
    this.size = 40,
    this.iconSize = 21,
    this.radius = 12,
  });

  final IconData icon;
  final AccentColorPair accent;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: accent.container,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(icon, size: iconSize, color: accent.icon),
  );
}
