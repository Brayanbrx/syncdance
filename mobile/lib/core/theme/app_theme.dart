import 'package:flutter/material.dart';

/// SyncDance's brand, the same as the web (frontend/src/styles.scss): a deep
/// indigo stage, orange for the left side of the body and sky blue for the
/// right one, as the practice paints the skeleton.
abstract final class Brand {
  static const ink = Color(0xFF1A1D45);
  static const stageDeep = Color(0xFF11133A);
  static const left = Color(0xFFFF8A3D);
  static const right = Color(0xFF4CC3F1);
  static const floor = Color(0xFFF2F5FA);
  static const line = Color(0xFFD7DCEA);
  static const muted = Color(0xFF5D6286);
  static const ok = Color(0xFF1D7A4F);
  static const warn = Color(0xFF9A5B00);
  static const danger = Color(0xFFB42318);

  static const display = 'Bricolage Grotesque';
  static const text = 'Atkinson Hyperlegible';
}

/// Brand colors the ColorScheme has no role for. Read them with
/// `Theme.of(context).extension<SyncColors>()!`.
@immutable
class SyncColors extends ThemeExtension<SyncColors> {
  const SyncColors({
    required this.stage,
    required this.onStage,
    required this.onStageMuted,
    required this.left,
    required this.right,
    required this.ok,
    required this.warn,
  });

  /// The indigo "stage" of hero blocks, in both themes.
  final Color stage, onStage, onStageMuted;

  /// Body sides: also the two-tone signature of the brand.
  final Color left, right;
  final Color ok, warn;

  static const light = SyncColors(
    stage: Brand.ink,
    onStage: Colors.white,
    onStageMuted: Color(0xFFC9CCEB),
    left: Brand.left,
    right: Brand.right,
    ok: Brand.ok,
    warn: Brand.warn,
  );

  static const dark = SyncColors(
    stage: Color(0xFF242960),
    onStage: Colors.white,
    onStageMuted: Color(0xFFC9CCEB),
    left: Brand.left,
    right: Brand.right,
    ok: Color(0xFF6FD3A0),
    warn: Color(0xFFFFC266),
  );

  /// The theme's brand colors; outside AppTheme (a bare MaterialApp in a
  /// test) the defaults for its brightness.
  static SyncColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SyncColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  SyncColors copyWith({
    Color? stage,
    Color? onStage,
    Color? onStageMuted,
    Color? left,
    Color? right,
    Color? ok,
    Color? warn,
  }) => SyncColors(
    stage: stage ?? this.stage,
    onStage: onStage ?? this.onStage,
    onStageMuted: onStageMuted ?? this.onStageMuted,
    left: left ?? this.left,
    right: right ?? this.right,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
  );

  @override
  SyncColors lerp(SyncColors? other, double t) {
    if (other == null) return this;
    return SyncColors(
      stage: Color.lerp(stage, other.stage, t)!,
      onStage: Color.lerp(onStage, other.onStage, t)!,
      onStageMuted: Color.lerp(onStageMuted, other.onStageMuted, t)!,
      left: Color.lerp(left, other.left, t)!,
      right: Color.lerp(right, other.right, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
    );
  }
}

abstract final class AppTheme {
  static ThemeData get light => _build(
    ColorScheme.fromSeed(seedColor: Brand.ink).copyWith(
      primary: Brand.ink,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE2E4F8),
      onPrimaryContainer: Brand.ink,
      secondary: Brand.left,
      onSecondary: Brand.ink,
      secondaryContainer: const Color(0xFFFFE4D2),
      onSecondaryContainer: const Color(0xFF5C2700),
      tertiary: Brand.right,
      onTertiary: Brand.stageDeep,
      tertiaryContainer: const Color(0xFFD6F2FD),
      onTertiaryContainer: const Color(0xFF00384D),
      error: Brand.danger,
      surface: Colors.white,
      onSurface: Brand.ink,
      onSurfaceVariant: Brand.muted,
      outline: const Color(0xFF8B90B3),
      outlineVariant: Brand.line,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F8FC),
      surfaceContainer: Brand.floor,
      surfaceContainerHigh: const Color(0xFFE9EDF6),
      surfaceContainerHighest: const Color(0xFFE1E6F1),
      surfaceTint: Colors.transparent,
    ),
    background: Brand.floor,
    sync: SyncColors.light,
  );

  static ThemeData get dark => _build(
    ColorScheme.fromSeed(
      seedColor: Brand.ink,
      brightness: Brightness.dark,
    ).copyWith(
      primary: Brand.right,
      onPrimary: Brand.stageDeep,
      primaryContainer: const Color(0xFF263070),
      onPrimaryContainer: const Color(0xFFDCE0FF),
      secondary: Brand.left,
      onSecondary: Brand.stageDeep,
      secondaryContainer: const Color(0xFF5C2E10),
      onSecondaryContainer: const Color(0xFFFFDCC5),
      tertiary: Brand.right,
      onTertiary: Brand.stageDeep,
      tertiaryContainer: const Color(0xFF0D4A63),
      onTertiaryContainer: const Color(0xFFD6F2FD),
      error: const Color(0xFFFF8A80),
      surface: const Color(0xFF161946),
      onSurface: const Color(0xFFEEF0FA),
      onSurfaceVariant: const Color(0xFFB7BBDD),
      outline: const Color(0xFF7C81B0),
      outlineVariant: const Color(0xFF34397A),
      surfaceContainerLowest: Brand.stageDeep,
      surfaceContainerLow: const Color(0xFF161946),
      surfaceContainer: const Color(0xFF1C2050),
      surfaceContainerHigh: const Color(0xFF242960),
      surfaceContainerHighest: const Color(0xFF2D3270),
      surfaceTint: Colors.transparent,
    ),
    background: Brand.stageDeep,
    sync: SyncColors.dark,
  );

  /// Titles in the brand's display face, narrow and heavy like the web.
  static TextStyle display(double weight, {double width = 85}) => TextStyle(
    fontFamily: Brand.display,
    fontWeight: weight >= 700 ? FontWeight.w800 : FontWeight.w600,
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
    ],
    letterSpacing: -0.2,
  );

  static TextTheme _text(Color body, Color muted) {
    final base = Typography.material2021().englishLike.apply(
      fontFamily: Brand.text,
      bodyColor: body,
      displayColor: body,
    );
    TextStyle? head(TextStyle? style, double weight, {double width = 85}) =>
        style?.merge(display(weight, width: width));
    return base.copyWith(
      displayLarge: head(base.displayLarge, 800, width: 75),
      displayMedium: head(base.displayMedium, 800, width: 75),
      displaySmall: head(base.displaySmall, 800, width: 78),
      headlineLarge: head(base.headlineLarge, 800, width: 80),
      headlineMedium: head(base.headlineMedium, 780, width: 80),
      headlineSmall: head(base.headlineSmall, 760, width: 82),
      titleLarge: head(base.titleLarge, 740, width: 85),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.bodySmall?.copyWith(color: muted, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required Color background,
    required SyncColors sync,
  }) {
    final text = _text(scheme.onSurface, scheme.onSurfaceVariant);
    final rounded = BorderRadius.circular(20);
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    const buttonSize = Size(64, 52);
    final buttonText = text.labelLarge?.copyWith(fontSize: 16);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: Brand.text,
      textTheme: text,
      scaffoldBackgroundColor: background,
      extensions: [sync],
      appBarTheme: AppBarThemeData(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 24),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: rounded,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: const StadiumBorder(),
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: const StadiumBorder(),
          textStyle: buttonText,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: const StadiumBorder(),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: field.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 32),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.headlineSmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: scheme.outlineVariant,
        circularTrackColor: Colors.transparent,
      ),
    );
  }
}
