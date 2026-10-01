import 'package:flutter/material.dart';

/// Shared look: petrol brand on warm paper, amber for returns and warnings.
const brandSeed = Color(0xff00625f);
const _paper = Color(0xfff6f4ef);

ThemeData marketTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: brandSeed,
        brightness: brightness,
      ).copyWith(
        primary: light ? brandSeed : null,
        surface: light ? _paper : null,
        surfaceContainerLowest: light ? Colors.white : null,
        // Calm petrol tint instead of the seed's saturated cyan containers.
        primaryContainer: light ? const Color(0xffd3ece8) : null,
        onPrimaryContainer: light ? const Color(0xff00302e) : null,
        secondaryContainer: light ? const Color(0xffd3ece8) : null,
        onSecondaryContainer: light ? const Color(0xff00302e) : null,
      );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      helperMaxLines: 4,
      errorMaxLines: 4,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: rounded,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
        backgroundColor: scheme.surfaceContainerLowest,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}

/// Keep important actions readable on compact phones and at large text sizes.
class AdaptiveActions extends StatelessWidget {
  final List<Widget> children;
  const AdaptiveActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth <
          400 * MediaQuery.textScalerOf(context).scale(14) / 14;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: children,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [for (final child in children) Expanded(child: child)],
      );
    },
  );
}

/// Summary figures retain their full text size when horizontal space runs out.
class FigureGroup extends StatelessWidget {
  final List<Figure> children;
  const FigureGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth <
          children.length *
              108 *
              MediaQuery.textScalerOf(context).scale(14) /
              14;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [for (final child in children) child.tile(context)],
        );
      }
      return Row(spacing: 8, children: children);
    },
  );
}

/// Amber tones for return mode, recovery and sync warnings.
class Tones {
  static bool _light(BuildContext c) =>
      Theme.of(c).brightness == Brightness.light;
  static Color warning(BuildContext c) =>
      _light(c) ? const Color(0xff8a4b00) : const Color(0xffffb870);
  static Color warningContainer(BuildContext c) =>
      _light(c) ? const Color(0xfffce8cf) : const Color(0xff4a2800);
  static Color onWarningContainer(BuildContext c) =>
      _light(c) ? const Color(0xff4a2800) : const Color(0xffffdcbe);
}

/// Small rounded label, e.g. "Demo" or "V2".
class Tag extends StatelessWidget {
  final String text;
  final Color background, foreground;
  const Tag(
    this.text, {
    super.key,
    required this.background,
    required this.foreground,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Labelled key figure tile, e.g. "Umsatz 412,50 €". Place inside a Row.
class Figure extends StatelessWidget {
  final String label, value;
  const Figure(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Expanded(child: tile(context));

  Widget tile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured message box for errors, warnings and results.
class Notice extends StatelessWidget {
  final String text;
  final bool error;
  const Notice(this.text, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = error ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: fg,
            ),
            Expanded(
              child: SelectableText(text, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
