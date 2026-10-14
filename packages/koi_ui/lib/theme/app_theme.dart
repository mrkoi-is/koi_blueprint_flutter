import 'package:flutter/material.dart';
import 'package:koi_ui/theme/app_colors.dart';
import 'package:koi_ui/theme/koi_material_theme.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

enum KoiAccent { moss, blue, violet }

abstract final class AppTheme {
  static ThemeData get light => build(brightness: Brightness.light);
  static ThemeData get dark => build(brightness: Brightness.dark);

  static ThemeData build({
    Brightness brightness = Brightness.light,
    KoiDensity density = KoiDensity.comfortable,
    KoiAccent accent = KoiAccent.moss,
  }) {
    final dark = brightness == Brightness.dark;
    final (lightAccent, darkAccent) = switch (accent) {
      KoiAccent.moss => (AppColors.moss, const Color(0xFF88BCAC)),
      KoiAccent.blue => (const Color(0xFF33589A), const Color(0xFFA8C7FA)),
      KoiAccent.violet => (const Color(0xFF7050A0), const Color(0xFFD0BCFF)),
    };
    final colors =
        ColorScheme.fromSeed(
          seedColor: lightAccent,
          brightness: brightness,
        ).copyWith(
          primary: dark ? darkAccent : lightAccent,
          onPrimary: dark ? AppColors.ink : Colors.white,
          secondaryContainer: dark
              ? const Color(0xFF303030)
              : const Color(0xFFEBEBEB),
          onSecondaryContainer: dark
              ? const Color(0xFFECECEC)
              : const Color(0xFF242424),
          secondary: dark ? const Color(0xFFE4B269) : AppColors.amber,
          // The custom amber replaces the seed color, so pair its foreground
          // explicitly instead of retaining the seed's white onSecondary.
          onSecondary: dark ? AppColors.ink : const Color(0xFF242424),
          surface: dark ? AppColors.nightContent : AppColors.content,
          surfaceDim: dark ? AppColors.nightContent : const Color(0xFFDEDEDE),
          surfaceBright: dark ? const Color(0xFF383838) : AppColors.content,
          surfaceContainerLowest: dark ? const Color(0xFF111111) : Colors.white,
          surfaceContainerHigh: dark
              ? const Color(0xFF303030)
              : const Color(0xFFEEEEEE),
          surfaceContainerHighest: dark
              ? const Color(0xFF363636)
              : const Color(0xFFE5E5E5),
          onSurface: dark ? const Color(0xFFECECEC) : const Color(0xFF242424),
          onSurfaceVariant: dark
              ? const Color(0xFFB8B8B8)
              : const Color(0xFF626262),
          inverseSurface: dark
              ? const Color(0xFFE8E8E8)
              : const Color(0xFF242424),
          onInverseSurface: dark
              ? const Color(0xFF242424)
              : const Color(0xFFF5F5F5),
          inversePrimary: dark ? lightAccent : darkAccent,
          surfaceContainerLow: dark
              ? const Color(0xFF232323)
              : const Color(0xFFF5F5F5),
          surfaceContainer: dark ? const Color(0xFF292929) : Colors.white,
          outline: dark ? const Color(0xFF767676) : const Color(0xFF787878),
          outlineVariant: dark
              ? const Color(0xFF3B3B3B)
              : const Color(0xFFDDDDDD),
        );
    final tokens = KoiThemeTokens.fromScheme(colors, density: density).copyWith(
      chromeBackground: dark ? AppColors.night : AppColors.chrome,
      contentBackground: colors.surface,
      panelBackground: dark ? AppColors.nightPanel : AppColors.panel,
      selectedBackground: dark
          ? const Color(0xFF303030)
          : const Color(0xFFEBEBEB),
      hoverBackground: dark ? const Color(0xFF262626) : const Color(0xFFF0F0F0),
      overlayBackground: colors.surfaceContainer,
    );
    // Keep Flutter's platform font and locale fallbacks, then define Koi roles.
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final text = base.textTheme.copyWith(
      titleSmall: base.textTheme.titleSmall!.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.textTheme.titleLarge!.copyWith(
        fontSize: 22,
        height: 30 / 22,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: base.textTheme.headlineSmall!.copyWith(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        height: 20 / 14,
      ),
      bodySmall: base.textTheme.bodySmall!.copyWith(
        fontSize: 12,
        height: 18 / 12,
        color: colors.onSurfaceVariant,
      ),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(
        fontSize: 16,
        height: 26 / 16,
      ),
      labelLarge: base.textTheme.labelLarge!.copyWith(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: base.textTheme.labelMedium!.copyWith(
        fontSize: 12,
        height: 18 / 12,
        fontWeight: FontWeight.w500,
      ),
    );
    return applyKoiMaterialTheme(base.copyWith(textTheme: text), tokens);
  }
}
