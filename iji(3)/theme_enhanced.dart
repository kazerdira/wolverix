import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Enhanced Wolverix Theme with atmospheric werewolf game styling
class WolverixTheme {
  // ============================================================================
  // PRIMARY COLORS - Dark mysterious palette
  // ============================================================================
  static const Color primaryColor = Color(0xFF7C4DFF);      // Deep purple
  static const Color primaryLight = Color(0xFFB47CFF);
  static const Color primaryDark = Color(0xFF3F1DCB);
  
  static const Color secondaryColor = Color(0xFFFF4081);    // Accent pink
  static const Color secondaryLight = Color(0xFFFF79B0);
  static const Color secondaryDark = Color(0xFFC60055);

  // ============================================================================
  // BACKGROUND COLORS - Atmospheric dark blues
  // ============================================================================
  static const Color backgroundColor = Color(0xFF0D1B2A);   // Deep night blue
  static const Color surfaceColor = Color(0xFF1B263B);      // Slightly lighter
  static const Color cardColor = Color(0xFF243B53);         // Card background
  static const Color cardColorLight = Color(0xFF334E68);    // Elevated cards
  
  // ============================================================================
  // ACCENT & GAME COLORS
  // ============================================================================
  static const Color accentColor = Color(0xFFE94560);       // Blood red accent
  static const Color moonGlow = Color(0xFFF5F3CE);          // Moon yellow
  static const Color forestGreen = Color(0xFF2D5A27);       // Forest atmosphere
  static const Color mistColor = Color(0xFF6B7B8C);         // Mysterious mist
  
  // ============================================================================
  // ROLE COLORS - Distinctive and thematic
  // ============================================================================
  static const Color werewolfColor = Color(0xFFDC143C);     // Crimson blood
  static const Color villagerColor = Color(0xFF4CAF50);     // Safe green
  static const Color seerColor = Color(0xFF9C27B0);         // Mystical purple
  static const Color witchColor = Color(0xFF00BCD4);        // Potion cyan
  static const Color hunterColor = Color(0xFFFF9800);       // Hunter orange
  static const Color cupidColor = Color(0xFFE91E63);        // Love pink
  static const Color bodyguardColor = Color(0xFF3F51B5);    // Shield blue
  static const Color tannerColor = Color(0xFF795548);       // Leather brown
  static const Color mediumColor = Color(0xFF607D8B);       // Spirit gray
  static const Color mayorColor = Color(0xFFFFD700);        // Gold

  // ============================================================================
  // TEXT COLORS
  // ============================================================================
  static const Color textPrimary = Color(0xFFF7F9FC);       // Crisp white
  static const Color textSecondary = Color(0xFFB0BEC5);     // Soft gray
  static const Color textHint = Color(0xFF607D8B);          // Muted
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark = Color(0xFFE8E8E8);

  // ============================================================================
  // STATUS COLORS
  // ============================================================================
  static const Color successColor = Color(0xFF00E676);      // Bright green
  static const Color errorColor = Color(0xFFFF5252);        // Bright red
  static const Color warningColor = Color(0xFFFFAB00);      // Amber
  static const Color infoColor = Color(0xFF40C4FF);         // Cyan

  // ============================================================================
  // GRADIENTS - For atmospheric effects
  // ============================================================================
  static const LinearGradient nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0D1B2A),
      Color(0xFF1B263B),
      Color(0xFF243B53),
    ],
  );

  static const LinearGradient dayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF2E4057),
      Color(0xFF4A6FA5),
      Color(0xFF7BA3D4),
    ],
  );

  static const LinearGradient bloodMoonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A0A0A),
      Color(0xFF3D1515),
      Color(0xFF5C1E1E),
    ],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, primaryLight],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentColor, secondaryColor],
  );

  static const LinearGradient werewolfGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B0000), werewolfColor],
  );

  static const LinearGradient villagerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E7D32), villagerColor],
  );

  // ============================================================================
  // SHADOWS - For depth and atmosphere
  // ============================================================================
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: primaryColor.withOpacity(0.1),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      color: primaryColor.withOpacity(0.4),
      blurRadius: 20,
      spreadRadius: 2,
    ),
  ];

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> getRoleShadow(String role) => [
    BoxShadow(
      color: getRoleColor(role).withOpacity(0.4),
      blurRadius: 16,
      spreadRadius: 2,
    ),
  ];

  // ============================================================================
  // BORDERS & DECORATIONS
  // ============================================================================
  static BorderRadius get borderRadiusSmall => BorderRadius.circular(8);
  static BorderRadius get borderRadiusMedium => BorderRadius.circular(12);
  static BorderRadius get borderRadiusLarge => BorderRadius.circular(16);
  static BorderRadius get borderRadiusXL => BorderRadius.circular(24);

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: cardColor,
    borderRadius: borderRadiusLarge,
    boxShadow: cardShadow,
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: surfaceColor.withOpacity(0.8),
    borderRadius: borderRadiusLarge,
    border: Border.all(
      color: Colors.white.withOpacity(0.1),
      width: 1,
    ),
    boxShadow: subtleShadow,
  );

  static BoxDecoration getRoleDecoration(String role) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        getRoleColor(role).withOpacity(0.3),
        getRoleColor(role).withOpacity(0.1),
      ],
    ),
    borderRadius: borderRadiusLarge,
    border: Border.all(
      color: getRoleColor(role).withOpacity(0.5),
      width: 2,
    ),
    boxShadow: getRoleShadow(role),
  );

  // ============================================================================
  // THEME DATA
  // ============================================================================
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: textOnPrimary,
        onSecondary: textOnPrimary,
        onSurface: textPrimary,
        onError: textOnPrimary,
        surfaceContainerHighest: cardColor,
      ),

      // App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: textPrimary,
        ),
      ),

      // Cards
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusLarge,
        ),
      ),

      // Elevated Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textOnPrimary,
          elevation: 8,
          shadowColor: primaryColor.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadiusMedium,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Outlined Buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadiusMedium,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Text Buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        border: OutlineInputBorder(
          borderRadius: borderRadiusMedium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusMedium,
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadiusMedium,
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadiusMedium,
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadiusMedium,
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: const TextStyle(color: textHint),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: borderRadiusMedium),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),

      // Dialog
      dialogTheme: DialogTheme(
        backgroundColor: surfaceColor,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusXL),
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: textHint,
        dragHandleSize: const Size(40, 4),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: textOnPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusLarge),
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withOpacity(0.3),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withOpacity(0.2),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: const TextStyle(color: textOnPrimary),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return textHint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor.withOpacity(0.5);
          return surfaceColor;
        }),
      ),

      // List Tile
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.1),
        thickness: 1,
        space: 1,
      ),

      // Tab Bar
      tabBarTheme: TabBarTheme(
        labelColor: primaryColor,
        unselectedLabelColor: textSecondary,
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        dividerColor: Colors.transparent,
      ),

      // Typography
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1,
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displaySmall: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textHint,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  /// Get color for a specific role
  static Color getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'werewolf':
        return werewolfColor;
      case 'villager':
        return villagerColor;
      case 'seer':
        return seerColor;
      case 'witch':
        return witchColor;
      case 'hunter':
        return hunterColor;
      case 'cupid':
        return cupidColor;
      case 'bodyguard':
        return bodyguardColor;
      case 'tanner':
        return tannerColor;
      case 'medium':
        return mediumColor;
      case 'mayor':
        return mayorColor;
      default:
        return villagerColor;
    }
  }

  /// Get gradient for a specific role
  static LinearGradient getRoleGradient(String role) {
    final color = getRoleColor(role);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.black, 0.3)!,
        color,
        Color.lerp(color, Colors.white, 0.2)!,
      ],
    );
  }

  /// Get icon for a specific role
  static IconData getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'werewolf':
        return Icons.pets;
      case 'villager':
        return Icons.person;
      case 'seer':
        return Icons.visibility;
      case 'witch':
        return Icons.science;
      case 'hunter':
        return Icons.gps_fixed;
      case 'cupid':
        return Icons.favorite;
      case 'bodyguard':
        return Icons.shield;
      case 'tanner':
        return Icons.construction;
      case 'medium':
        return Icons.auto_fix_high;
      case 'mayor':
        return Icons.emoji_events;
      default:
        return Icons.person;
    }
  }

  /// Get gradient for game phase (night/day)
  static LinearGradient getPhaseGradient(bool isNight) {
    return isNight ? nightGradient : dayGradient;
  }
}
