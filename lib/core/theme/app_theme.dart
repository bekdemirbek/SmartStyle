import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color lightBackground = backgroundPrimaryLight;
  static const Color lightCard = surface1Light;
  static const Color lightPrimary = accentGoldMidLight;
  static const Color lightText = textPrimaryLight;
  static const Color lightSubText = textSecondaryLight;
  static const Color lightBorder = borderMediumLight;

  static const Color darkBackground = backgroundPrimary;
  static const Color darkCard = surface1;
  static const Color darkPrimary = accentGoldMid;
  static const Color darkAccent = accentGoldLight;
  static const Color darkText = textPrimary;
  static const Color darkSubText = textSecondary;

  static const Color backgroundPrimary = Color(0xFF111114);
  static const Color surface1 = Color(0xFF18181D);
  static const Color surface2 = Color(0xFF202127);
  static const Color surface3 = Color(0xFF2C2D34);

  static const Color accentGoldLight = Color(0xFFE8CC7A);
  static const Color accentGoldMid = Color(0xFFC9A84C);
  static const Color accentGoldDark = Color(0xFFA07820);
  static const Color accentGlow = Color(0x26C9A84C);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFBBBBBB);
  static const Color textTertiary = Color(0xFF888888);
  static const Color textOnGold = Color(0xFF000000);
  static const Color textOnGoldSoft = Color(0xFF1A1100);
  static const Color goldDim = Color(0x33C9A84C);

  static const Color borderSubtle = Color(0x14FFFFFF);
  static const Color borderMedium = Color(0x26FFFFFF);

  static const Color backgroundPrimaryLight = Color(0xFFF5F2ED);
  static const Color surface1Light = Color(0xFFFDFAF6);
  static const Color surface2Light = Color(0xFFF0EDE7);
  static const Color surface3Light = Color(0xFFE8E4DC);

  static const Color accentGoldLightMode = Color(0xFF8B6914);
  static const Color accentGoldMidLight = Color(0xFFC9A84C);

  static const Color textPrimaryLight = Color(0xFF1A1714);
  static const Color textSecondaryLight = Color(0xFF6B6560);
  static const Color textTertiaryLight = Color(0xFFA8A49E);

  static const Color borderSubtleLight = Color(0x0F000000);
  static const Color borderMediumLight = Color(0x1A000000);

  static const double radiusCard = 20.0;
  static const double radiusButton = 14.0;
  static const double radiusPill = 100.0;
  static const double radiusInput = 16.0;
  static const double radiusSmall = 10.0;
  static const double radiusUpload = 24.0;

  static const double screenPadding = 20.0;
  static const double cardGap = 12.0;
  static const double sectionGap = 32.0;

  static const LinearGradient goldGradient = LinearGradient(
    colors: [accentGoldLight, accentGoldMid, accentGoldDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradientLightMode = LinearGradient(
    colors: [accentGoldLightMode, accentGoldMidLight, accentGoldLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData lightTheme = _buildLightTheme();
  static ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accentGoldMid,
        secondary: accentGoldLight,
        surface: surface1,
        error: Color(0xFFE24B4A),
      ),
    );

    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(isDark: true),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textPrimary,
      ),
      cardColor: surface1,
      dividerColor: borderSubtle,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentGoldMid.withOpacity(0.55);
          }
          return surface3;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGoldMid,
          foregroundColor: backgroundPrimary,
          elevation: 0,
          textStyle: _bodyStyle(isDark: true).copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: _captionStyle(isDark: true).copyWith(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: accentGoldMid),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderSubtle),
        ),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundPrimaryLight,
      colorScheme: const ColorScheme.light(
        primary: accentGoldLightMode,
        secondary: accentGoldMidLight,
        surface: surface1Light,
        error: Color(0xFFE24B4A),
      ),
    );

    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(isDark: false),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textPrimaryLight,
      ),
      cardColor: surface1Light,
      dividerColor: borderSubtleLight,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentGoldMidLight.withOpacity(0.55);
          }
          return surface3Light;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGoldMidLight,
          foregroundColor: textPrimaryLight,
          elevation: 0,
          textStyle: _bodyStyle(isDark: false).copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2Light,
        hintStyle: _captionStyle(isDark: false).copyWith(
          color: textSecondaryLight,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderSubtleLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: accentGoldMidLight),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderSubtleLight),
        ),
      ),
    );
  }

  static TextTheme _textTheme({required bool isDark}) {
    return TextTheme(
      displayLarge: _heading1Style(isDark: isDark),
      displayMedium: _heading1Style(isDark: isDark),
      headlineSmall: _heading2Style(isDark: isDark),
      titleLarge: _heading2Style(isDark: isDark),
      bodyLarge: _bodyStyle(isDark: isDark),
      bodyMedium: _bodyStyle(isDark: isDark),
      labelLarge: _labelStyle(isDark: isDark),
      labelMedium: _captionStyle(isDark: isDark),
    );
  }

  static TextStyle _heading1Style({required bool isDark}) {
    return GoogleFonts.playfairDisplay(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.5,
      color: isDark ? textPrimary : textPrimaryLight,
    );
  }

  static TextStyle _heading2Style({required bool isDark}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: isDark ? textPrimary : textPrimaryLight,
    );
  }

  static TextStyle _labelStyle({required bool isDark}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.8,
      color: isDark ? textSecondary : textSecondaryLight,
    );
  }

  static TextStyle _bodyStyle({required bool isDark}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: isDark ? textPrimary : textPrimaryLight,
    );
  }

  static TextStyle _captionStyle({required bool isDark}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: isDark ? textSecondary : textSecondaryLight,
    );
  }

  static Color bg(bool isDark) => isDark ? backgroundPrimary : backgroundPrimaryLight;
  static Color card(bool isDark) => isDark ? surface1 : surface1Light;
  static Color layer2(bool isDark) => isDark ? surface2 : surface2Light;
  static Color layer3(bool isDark) => isDark ? surface3 : surface3Light;
  static Color primaryText(bool isDark) => isDark ? textPrimary : textPrimaryLight;
  static Color secondaryText(bool isDark) =>
      isDark ? textSecondary : textSecondaryLight;
  static Color tertiaryText(bool isDark) =>
      isDark ? textTertiary : textTertiaryLight;
  static Color subtleBorder(bool isDark) =>
      isDark ? borderSubtle : borderSubtleLight;
  static Color mediumBorder(bool isDark) =>
      isDark ? borderMedium : borderMediumLight;
  static Color gold(bool isDark) => isDark ? accentGoldMid : accentGoldMidLight;
  static Gradient themeGoldGradient(bool isDark) =>
      isDark ? goldGradient : goldGradientLightMode;

  static TextStyle heading1(bool isDark) => _heading1Style(isDark: isDark);
  static TextStyle heading2(bool isDark) => _heading2Style(isDark: isDark);
  static TextStyle label(bool isDark) => _labelStyle(isDark: isDark);
  static TextStyle body(bool isDark) => _bodyStyle(isDark: isDark);
  static TextStyle caption(bool isDark) => _captionStyle(isDark: isDark);
  static TextStyle screenTitle(bool isDark) => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: primaryText(isDark),
      );
  static TextStyle sectionTitle(bool isDark) => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: primaryText(isDark),
      );
  static TextStyle cardTitle(bool isDark) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: primaryText(isDark),
      );
  static TextStyle bodyText(bool isDark) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: primaryText(isDark),
      );
  static TextStyle captionText(bool isDark) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: secondaryText(isDark),
      );

  static List<BoxShadow> cardShadow(bool isDark) {
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.24 : 0.08),
        blurRadius: isDark ? 20 : 16,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static BoxDecoration panelDecoration(bool isDark, {double radius = radiusCard}) {
    return BoxDecoration(
      color: card(isDark),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: subtleBorder(isDark), width: 0.6),
      boxShadow: cardShadow(isDark),
    );
  }

  static BoxDecoration frostedDecoration(bool isDark, {double radius = radiusCard}) {
    return BoxDecoration(
      color: isDark
          ? const Color(0xD118181D)
          : const Color(0xCCF5F2ED),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: subtleBorder(isDark), width: 0.5),
      boxShadow: cardShadow(isDark),
    );
  }

  static Widget auroraBackground({required bool isDark, required Widget child}) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          left: -80,
          child: _AuroraGlow(
            size: 260,
            colors: [
              accentGoldMid.withOpacity(isDark ? 0.14 : 0.10),
              accentGoldLight.withOpacity(isDark ? 0.04 : 0.02),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          top: -80,
          right: -100,
          child: _AuroraGlow(
            size: 280,
            colors: [
              const Color(0xFF5F3A6B).withOpacity(isDark ? 0.12 : 0.08),
              const Color(0xFF7E5A88).withOpacity(isDark ? 0.04 : 0.02),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          bottom: 80,
          left: -120,
          child: _AuroraGlow(
            size: 240,
            colors: [
              accentGoldDark.withOpacity(isDark ? 0.08 : 0.06),
              Colors.transparent,
            ],
          ),
        ),
        child,
      ],
    );
  }

  static Widget frosted({
    required bool isDark,
    required Widget child,
    double radius = radiusCard,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: frostedDecoration(isDark, radius: radius),
          child: child,
        ),
      ),
    );
  }
}

class _AuroraGlow extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _AuroraGlow({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
