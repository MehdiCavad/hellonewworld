import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

/// Rankd's design tokens. Dark is the signature look; light shares every
/// rule and only swaps the palette.
@immutable
class RankdColors extends ThemeExtension<RankdColors> {
  const RankdColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.text2,
    required this.muted,
    required this.glowA,
    required this.glowB,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color text;
  final Color text2;
  final Color muted;
  final Color glowA;
  final Color glowB;

  static const brand = Color(0xFF7C5CFF);
  static const brand2 = Color(0xFFB14DFF);
  static const brand3 = Color(0xFFFF5D7A);
  static const good = Color(0xFF3DDC84);
  static const bad = Color(0xFFFF6369);
  static const gold = Color(0xFFFFC53D);
  static const silver = Color(0xFFB8C4D6);
  static const bronze = Color(0xFFE08A4B);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brand2, brand3],
    stops: [0, .5, 1],
  );

  static const dark = RankdColors(
    bg: Color(0xFF09090D),
    surface: Color(0xFF14141C),
    surface2: Color(0xFF1C1C27),
    border: Color(0x1FFFFFFF),
    text: Color(0xFFF2F2F8),
    text2: Color(0xFFBDBDD0),
    muted: Color(0xFF85859E),
    glowA: Color(0x407C5CFF),
    glowB: Color(0x26FF5D7A),
  );

  static const light = RankdColors(
    bg: Color(0xFFF6F5FB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0EFF7),
    border: Color(0x14000000),
    text: Color(0xFF13131B),
    text2: Color(0xFF4A4A5E),
    muted: Color(0xFF7D7D92),
    glowA: Color(0x267C5CFF),
    glowB: Color(0x1AFF5D7A),
  );

  @override
  RankdColors copyWith() => this;

  @override
  RankdColors lerp(ThemeExtension<RankdColors>? other, double t) {
    if (other is! RankdColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RankdColors(
      bg: l(bg, other.bg), surface: l(surface, other.surface), surface2: l(surface2, other.surface2),
      border: l(border, other.border), text: l(text, other.text), text2: l(text2, other.text2),
      muted: l(muted, other.muted), glowA: l(glowA, other.glowA), glowB: l(glowB, other.glowB),
    );
  }
}

extension RankdTheme on BuildContext {
  RankdColors get c => Theme.of(this).extension<RankdColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  TextTheme get t => Theme.of(this).textTheme;
}

const display = 'Bricolage';
const body = 'Inter';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? RankdColors.dark : RankdColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: RankdColors.brand,
    brightness: brightness,
    surface: c.surface,
  ).copyWith(primary: RankdColors.brand, secondary: RankdColors.brand3);

  TextStyle d(double size, FontWeight w, {double ls = -0.5, double h = 1.1}) =>
      TextStyle(fontFamily: display, fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c.text);
  TextStyle b(double size, FontWeight w, {Color? color, double h = 1.4}) =>
      TextStyle(fontFamily: body, fontSize: size, fontWeight: w, height: h, color: color ?? c.text);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: body,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
    textTheme: TextTheme(
      displayLarge: d(44, FontWeight.w800, ls: -1.6, h: 1.02),
      displayMedium: d(34, FontWeight.w800, ls: -1.1, h: 1.05),
      displaySmall: d(28, FontWeight.w700, ls: -0.8),
      headlineMedium: d(22, FontWeight.w700, ls: -0.5),
      titleLarge: d(19, FontWeight.w700, ls: -0.3),
      titleMedium: b(16, FontWeight.w600),
      titleSmall: b(14, FontWeight.w600),
      bodyLarge: b(16, FontWeight.w400),
      bodyMedium: b(14, FontWeight.w400, color: c.text2),
      bodySmall: b(12.5, FontWeight.w500, color: c.muted),
      labelLarge: b(15, FontWeight.w600),
      labelMedium: b(13, FontWeight.w600),
      labelSmall: b(11, FontWeight.w600, color: c.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.text,
      systemOverlayStyle: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.muted.withValues(alpha: .4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.text,
      contentTextStyle: b(14, FontWeight.w500, color: c.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/// The topic's two-stop gradient, hue-shifted for depth.
LinearGradient topicGradient(Color accent, {double shift = 32}) {
  final hsl = HSLColor.fromColor(accent);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      hsl.withLightness((hsl.lightness + .04).clamp(0, .7)).toColor(),
      hsl.withHue((hsl.hue + shift) % 360).withLightness((hsl.lightness - .16).clamp(.22, 1)).toColor(),
    ],
  );
}

/// A per-item gradient around the topic accent, so neighbouring cards differ.
LinearGradient itemGradient(Color accent, String seed) {
  final hash = seed.codeUnits.fold<int>(17, (a, c) => (a * 31 + c) & 0x7FFFFFFF);
  final hsl = HSLColor.fromColor(accent);
  final h = (hsl.hue + (hash % 50) - 25) % 360;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      HSLColor.fromAHSL(1, h, (hsl.saturation * .95).clamp(.4, 1), .58).toColor(),
      HSLColor.fromAHSL(1, (h + 38) % 360, (hsl.saturation).clamp(.45, 1), .32).toColor(),
    ],
  );
}
