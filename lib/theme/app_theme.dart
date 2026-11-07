import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0A0A);
  static const card = Color(0xFF161616);
  static const cardAlt = Color(0xFF1E1E1E);
  static const red = Color(0xFFE50914);
  static const redDark = Color(0xFF8C050B);
  static const text = Color(0xFFF5F5F5);
  static const textDim = Color(0xFF9A9A9A);
  static const green = Color(0xFF2ECC71);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.red,
      secondary: AppColors.red,
      surface: AppColors.card,
    ),
    textTheme: GoogleFonts.vazirmatnTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.red.withOpacity(0.25),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.red,
      foregroundColor: Colors.white,
    ),
  );
}
