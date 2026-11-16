import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/app_theme.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _compositeOver(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.fromARGB(
    255,
    ((foreground.r * alpha + background.r * (1 - alpha)) * 255).round(),
    ((foreground.g * alpha + background.g * (1 - alpha)) * 255).round(),
    ((foreground.b * alpha + background.b * (1 - alpha)) * 255).round(),
  );
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    test('$name semantic text roles meet WCAG AA contrast', () {
      final scheme = theme.colorScheme;
      final semantic = theme.extension<AppSemanticColors>()!;
      final accents = theme.extension<AccentColors>()!;
      final pairs = [
        ('header deep', semantic.onHeader, semantic.headerDeep),
        ('header light', semantic.onHeader, semantic.headerLight),
        ('primary', scheme.onPrimary, scheme.primary),
        ('primary on surface', scheme.primary, scheme.surface),
        (
          'primary container',
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        (
          'primary on primary container',
          scheme.primary,
          scheme.primaryContainer,
        ),
        ('surface', scheme.onSurface, scheme.surface),
        ('surface variant', scheme.onSurfaceVariant, semantic.surfaceVariant),
        ('success', semantic.onSuccess, semantic.success),
        ('success on surface', semantic.success, scheme.surface),
        (
          'success container',
          semantic.onSuccessContainer,
          semantic.successContainer,
        ),
        ('warning', semantic.onWarning, semantic.warning),
        ('warning on surface', semantic.warning, scheme.surface),
        (
          'warning container',
          semantic.onWarningContainer,
          semantic.warningContainer,
        ),
        ('error', scheme.onError, scheme.error),
        ('error on surface', scheme.error, scheme.surface),
        ('error container', scheme.onErrorContainer, scheme.errorContainer),
      ];

      for (final (role, foreground, background) in pairs) {
        expect(
          _contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: '$role contrast in $name theme',
        );
      }
      expect(
        _contrast(scheme.outlineVariant, scheme.surface),
        greaterThanOrEqualTo(3),
        reason: 'outline contrast in $name theme',
      );
      for (final surface in [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ]) {
        expect(
          _contrast(scheme.onSurface, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'onSurface contrast on $surface in $name theme',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'onSurfaceVariant contrast on $surface in $name theme',
        );
      }
      for (final (accentName, accent) in [
        ('teal', accents.teal),
        ('green', accents.green),
        ('blue', accents.blue),
        ('amber', accents.amber),
        ('violet', accents.violet),
        ('rose', accents.rose),
      ]) {
        expect(
          _contrast(accent.icon, accent.container),
          greaterThanOrEqualTo(3),
          reason: '$accentName icon contrast in $name theme',
        );
      }
      expect(
        _contrast(accents.green.icon, semantic.successContainer),
        greaterThanOrEqualTo(3),
        reason: 'classified icon contrast in $name theme',
      );
      expect(
        _contrast(accents.amber.icon, semantic.warningContainer),
        greaterThanOrEqualTo(3),
        reason: 'unclassified icon contrast in $name theme',
      );
      expect(
        theme.appBarTheme.backgroundColor,
        semantic.headerDeep,
        reason: 'consistent branded app bar in $name theme',
      );
      expect(
        theme.navigationBarTheme.indicatorColor,
        accents.teal.container,
        reason: 'consistent teal navigation indicator in $name theme',
      );
    });

    test('$name hero progress fills contrast with their track', () {
      final semantic = theme.extension<AppSemanticColors>()!;
      final trackColors = [
        _compositeOver(semantic.headerTrack, semantic.headerDeep),
        _compositeOver(semantic.headerTrack, semantic.headerLight),
      ];
      final isLight = theme.brightness == Brightness.light;
      final stateColors = [
        isLight ? semantic.success : semantic.onSuccessContainer,
        isLight ? semantic.warning : semantic.onWarningContainer,
        isLight ? theme.colorScheme.error : theme.colorScheme.onErrorContainer,
      ];

      for (final (index, fill) in stateColors.indexed) {
        for (final track in trackColors) {
          expect(
            _contrast(fill, track),
            greaterThanOrEqualTo(3),
            reason: 'progress state $index in $name theme: $fill on $track',
          );
        }
      }
    });

    test('$name surface roles are neutral', () {
      final scheme = theme.colorScheme;
      final semantic = theme.extension<AppSemanticColors>()!;
      final surfaces = [
        scheme.surface,
        semantic.surfaceVariant,
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];

      for (final surface in surfaces) {
        expect(
          HSLColor.fromColor(surface).saturation,
          lessThan(0.08),
          reason: 'surface $surface in $name theme',
        );
      }
    });
  }
}
