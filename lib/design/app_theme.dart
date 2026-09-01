import 'package:flutter/cupertino.dart';

abstract final class AppPalette {
  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F2F7),
    darkColor: Color(0xFF000000),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xF2121214),
  );
  static const raisedSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xF51C1C1F),
  );
  static const softSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F2F7),
    darkColor: Color(0xD12A2A2E),
  );
  static const sidebar = CupertinoDynamicColor.withBrightness(
    color: Color(0xEEF0F0F5),
    darkColor: Color(0xB30E0E11),
  );
  static const text = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1D1D1F),
    darkColor: Color(0xFFF5F5F7),
  );
  static const secondaryText = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF6E6E73),
    darkColor: Color(0xFFA1A1A6),
  );
  static const separator = CupertinoDynamicColor.withBrightness(
    color: Color(0x293C3C43),
    darkColor: Color(0x38FFFFFF),
  );
  static const blue = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF007AFF),
    darkColor: Color(0xFF0A84FF),
  );
  static const blueSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEAF3FF),
    darkColor: Color(0xB31B3553),
  );
  static const green = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF248A3D),
    darkColor: Color(0xFF30D158),
  );
  static const greenSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEAF8EE),
    darkColor: Color(0xB3163821),
  );
  static const orange = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFC65F00),
    darkColor: Color(0xFFFF9F0A),
  );
  static const orangeSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFF3E4),
    darkColor: Color(0xB3402C13),
  );
  static const red = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFD70015),
    darkColor: Color(0xFFFF453A),
  );
  static const redSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFF0F0),
    darkColor: Color(0xB348171A),
  );
  static const purple = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF7857D8),
    darkColor: Color(0xFFBF5AF2),
  );
  static const purpleSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF1EDFF),
    darkColor: Color(0xB3291F46),
  );

  static Color resolve(BuildContext context, Color color) {
    return CupertinoDynamicColor.resolve(color, context);
  }
}

abstract final class AppTextStyles {
  static const largeTitle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.1,
    height: 1.12,
  );
  static const title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.65,
    height: 1.18,
  );
  static const sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
}

CupertinoThemeData buildCupertinoTheme() {
  return const CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: AppPalette.blue,
    scaffoldBackgroundColor: AppPalette.background,
    barBackgroundColor: AppPalette.sidebar,
    textTheme: CupertinoTextThemeData(
      primaryColor: AppPalette.blue,
      textStyle: TextStyle(
        color: AppPalette.text,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      actionTextStyle: TextStyle(
        color: AppPalette.blue,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      navTitleTextStyle: TextStyle(
        color: AppPalette.text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      navLargeTitleTextStyle: AppTextStyles.largeTitle,
    ),
  );
}
