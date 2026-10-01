import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Monochrome design system.
///
/// One hue family only: paper white through ink black, and its inverse in the
/// dark palette. Meaning is carried by *fill inversion, weight, border and
/// glyph* — never by colour. That keeps the interface calm, prints well, and
/// reads identically for colour-blind users.
///
/// Both palettes share token *names*, so a widget written against
/// [AppColors.ink] is correct in either theme: `ink` always means "the colour
/// text is drawn in", not "black".
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.sunk,
    required this.sunkStrong,
    required this.hairline,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.ink2,
    required this.muted,
    required this.faint,
    required this.onInk,
  });

  final Brightness brightness;

  /// App background.
  final Color canvas;

  /// Cards, sheets, dialogs.
  final Color surface;

  /// Inset wells, skeletons, quiet fills.
  final Color sunk;

  /// Deeper well, for selected and quiet-emphasis fills.
  final Color sunkStrong;

  /// 1px separators and card borders.
  final Color hairline;

  /// Stronger border: focus rings, outlined "solid" states.
  final Color line;

  /// Primary text and the "on" fill — black on light, white on dark.
  final Color ink;

  /// Pressed/hover shade of [ink].
  final Color inkSoft;

  /// Body text that should recede a step.
  final Color ink2;

  /// Labels and secondary text.
  final Color muted;

  /// Placeholders, disabled text, tertiary metadata.
  final Color faint;

  /// Text and icons drawn on top of an [ink] fill.
  final Color onInk;

  bool get isDark => brightness == Brightness.dark;

  /// Warm paper. Off-white canvas so white cards separate without shadows.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFFAFAF9),
    surface: Color(0xFFFFFFFF),
    sunk: Color(0xFFF5F5F4),
    sunkStrong: Color(0xFFEDEBE9),
    hairline: Color(0xFFE7E5E4),
    line: Color(0xFFD6D3D1),
    ink: Color(0xFF0C0A09),
    inkSoft: Color(0xFF1C1917),
    ink2: Color(0xFF44403C),
    muted: Color(0xFF78716C),
    faint: Color(0xFFA8A29E),
    onInk: Color(0xFFFFFFFF),
  );

  /// Warm charcoal rather than pure black: true #000 makes the hairlines this
  /// system relies on disappear, and smears on OLED while scrolling.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B0B0A),
    surface: Color(0xFF161615),
    sunk: Color(0xFF1F1F1D),
    sunkStrong: Color(0xFF2B2B28),
    hairline: Color(0xFF2A2A27),
    line: Color(0xFF44443F),
    ink: Color(0xFFFAFAF9),
    inkSoft: Color(0xFFEDEBE9),
    ink2: Color(0xFFD6D3D1),
    muted: Color(0xFFA8A29E),
    faint: Color(0xFF78716C),
    onInk: Color(0xFF0C0A09),
  );
}

/// The active palette, read by every widget.
///
/// Held globally and swapped by [ThemeController] so the 300-odd existing
/// `AppColors.x` call sites keep working unchanged. The trade-off is that the
/// tokens are no longer `const`; the app rebuilds from the root on a change.
class AppColors {
  const AppColors._();

  /// The active palette. [ThemeController] owns writes to this.
  static AppPalette palette = AppPalette.light;

  static AppPalette get _active => palette;

  static Color get canvas => _active.canvas;
  static Color get surface => _active.surface;
  static Color get sunk => _active.sunk;
  static Color get sunkStrong => _active.sunkStrong;
  static Color get hairline => _active.hairline;
  static Color get line => _active.line;
  static Color get ink => _active.ink;
  static Color get inkSoft => _active.inkSoft;
  static Color get ink2 => _active.ink2;
  static Color get muted => _active.muted;
  static Color get faint => _active.faint;
  static Color get onInk => _active.onInk;

  // ------------------------------------------- legacy aliases (monochrome)
  static Color get background => canvas;
  static Color get card => surface;
  static Color get foreground => ink;
  static Color get border => hairline;
  static Color get primary => ink;
  static Color get primaryForeground => onInk;
  static Color get positive => ink;
  static Color get danger => ink;
  static Color get neutral => muted;
}

/// Corner radii. Small family, used consistently.
class Radii {
  const Radii._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Spacing scale (4pt grid).
class Insets {
  const Insets._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;

  /// Standard horizontal page gutter.
  static const double gutter = 20;
}

/// Type scale. System font, tuned tracking — in a monochrome interface,
/// typography does the work colour normally does.
class AppText {
  const AppText._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The single biggest number on a screen (the live clock, a total).
  static TextStyle get display => TextStyle(
    fontSize: 44,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.6,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  /// Screen titles.
  static TextStyle get title => TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.7,
    color: AppColors.ink,
  );

  /// Card and sheet headings.
  static TextStyle get heading => TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  /// Row titles, emphasised body.
  static TextStyle get subhead => TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.ink,
  );

  static TextStyle get body => TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.ink2,
  );

  static TextStyle get bodySm => TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Uppercase eyebrow above a value or section. The system's signature.
  static TextStyle get eyebrow => TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: AppColors.muted,
  );

  /// Numbers that must align in columns (times, durations, counts).
  static TextStyle get numeral => TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static TextStyle get numeralLg => TextStyle(
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static TextStyle get button => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
}

/// How a status paints itself without using colour.
///
/// [fill] / [ink] / [border] form the surface; [glyph] gives a second,
/// non-typographic channel so a status is legible at a glance and in a
/// 28px calendar cell.
class StatusTone {
  const StatusTone({
    required this.fill,
    required this.ink,
    required this.border,
    required this.glyph,
    this.emphasis = false,
  });

  final Color fill;
  final Color ink;
  final Color border;
  final IconData glyph;

  /// True for the "live" state, which is drawn inverted (black on white).
  final bool emphasis;

  // Kept for call sites that predate the token rename.
  Color get background => fill;
  Color get foreground => ink;
}

/// Status tones, resolved against the active palette.
///
/// `ink` is the foreground of the current theme, so "PRESENT is inverted"
/// holds in both: black-on-white in light, white-on-black in dark.
Map<String, StatusTone> get statusTones => {
  // Present is the only inverted tone: today, right now, you are counted.
  'PRESENT': StatusTone(
    fill: AppColors.ink,
    ink: AppColors.onInk,
    border: AppColors.ink,
    glyph: Icons.circle,
    emphasis: true,
  ),
  'CHECKED_OUT': StatusTone(
    fill: AppColors.surface,
    ink: AppColors.ink,
    border: AppColors.ink,
    glyph: Icons.check_rounded,
  ),
  'WFH': StatusTone(
    fill: AppColors.sunkStrong,
    ink: AppColors.ink,
    border: AppColors.line,
    glyph: Icons.house_outlined,
  ),
  'HOLIDAY': StatusTone(
    fill: AppColors.sunk,
    ink: AppColors.muted,
    border: AppColors.hairline,
    glyph: Icons.wb_sunny_outlined,
  ),
  'LEAVE': StatusTone(
    fill: AppColors.sunk,
    ink: AppColors.muted,
    border: AppColors.hairline,
    glyph: Icons.event_busy_outlined,
  ),
  'ABSENT': StatusTone(
    fill: AppColors.surface,
    ink: AppColors.muted,
    border: AppColors.line,
    glyph: Icons.remove_rounded,
  ),
  'MANUAL_OVERRIDE': StatusTone(
    fill: AppColors.sunkStrong,
    ink: AppColors.ink,
    border: AppColors.line,
    glyph: Icons.edit_outlined,
  ),
};

StatusTone toneFor(String? status) =>
    statusTones[status] ??
    StatusTone(
      fill: AppColors.surface,
      ink: AppColors.faint,
      border: AppColors.hairline,
      glyph: Icons.more_horiz_rounded,
    );

ColorScheme _scheme() => ColorScheme(
  brightness: AppColors.palette.brightness,
  primary: AppColors.ink,
  onPrimary: AppColors.onInk,
  primaryContainer: AppColors.sunkStrong,
  onPrimaryContainer: AppColors.ink,
  secondary: AppColors.ink2,
  onSecondary: AppColors.onInk,
  secondaryContainer: AppColors.sunk,
  onSecondaryContainer: AppColors.ink,
  tertiary: AppColors.muted,
  onTertiary: AppColors.onInk,
  tertiaryContainer: AppColors.sunk,
  onTertiaryContainer: AppColors.ink,
  error: AppColors.ink,
  onError: AppColors.onInk,
  errorContainer: AppColors.sunkStrong,
  onErrorContainer: AppColors.ink,
  surface: AppColors.surface,
  onSurface: AppColors.ink,
  surfaceContainerLowest: AppColors.surface,
  surfaceContainerLow: AppColors.canvas,
  surfaceContainer: AppColors.sunk,
  surfaceContainerHigh: AppColors.sunkStrong,
  surfaceContainerHighest: AppColors.sunkStrong,
  onSurfaceVariant: AppColors.muted,
  outline: AppColors.line,
  outlineVariant: AppColors.hairline,
  shadow: AppColors.ink,
  scrim: AppColors.ink,
  inverseSurface: AppColors.ink,
  onInverseSurface: AppColors.onInk,
  inversePrimary: AppColors.onInk,
);

OutlineInputBorder _inputBorder(Color color, [double width = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: color, width: width),
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: _scheme(),
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    canvasColor: AppColors.canvas,
    dividerColor: AppColors.hairline,
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: Insets.gutter,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: AppText.heading,
      iconTheme: IconThemeData(color: AppColors.ink, size: 22),
    ),
    iconTheme: IconThemeData(color: AppColors.ink2, size: 20),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      titleTextStyle: AppText.subhead,
      subtitleTextStyle: AppText.bodySm,
      contentPadding: EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.xs),
      minVerticalPadding: Insets.md,
      horizontalTitleGap: Insets.md,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: false,
      contentPadding: EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.lg,
      ),
      hintStyle: TextStyle(color: AppColors.faint, fontSize: 15),
      labelStyle: TextStyle(color: AppColors.muted, fontSize: 15),
      floatingLabelStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: AppText.bodySm,
      errorStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      border: _inputBorder(AppColors.hairline),
      enabledBorder: _inputBorder(AppColors.hairline),
      focusedBorder: _inputBorder(AppColors.ink, 1.6),
      errorBorder: _inputBorder(AppColors.ink, 1.6),
      focusedErrorBorder: _inputBorder(AppColors.ink, 1.6),
      disabledBorder: _inputBorder(AppColors.hairline),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(52),
        padding: EdgeInsets.symmetric(horizontal: Insets.lg),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.onInk,
        disabledBackgroundColor: AppColors.sunkStrong,
        disabledForegroundColor: AppColors.faint,
        elevation: 0,
        textStyle: AppText.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ).copyWith(
        overlayColor: WidgetStatePropertyAll(Color(0x1FFFFFFF)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(52),
        padding: EdgeInsets.symmetric(horizontal: Insets.lg),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        disabledForegroundColor: AppColors.faint,
        textStyle: AppText.button,
        side: BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ).copyWith(
        overlayColor: WidgetStatePropertyAll(AppColors.sunk),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: AppText.button,
        minimumSize: Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink2,
        minimumSize: Size(44, 44),
        highlightColor: AppColors.sunk,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.ink,
      foregroundColor: AppColors.onInk,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: StadiumBorder(),
      extendedTextStyle: AppText.button,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.sunkStrong,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: AppColors.muted, size: 22),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11.5,
          letterSpacing: 0.1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.ink : AppColors.muted,
        );
      }),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppText.heading,
      contentTextStyle: AppText.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: AppColors.hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        color: AppColors.onInk,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: AppColors.onInk,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.muted,
      labelStyle: AppText.subhead,
      unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.hairline,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.ink, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      checkmarkColor: AppColors.onInk,
      side: BorderSide(color: AppColors.line),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.onInk,
      ),
      padding: EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
      shape: StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.onInk
            : AppColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.ink
            : AppColors.sunkStrong,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.ink
            : AppColors.line,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.sunkStrong,
      circularTrackColor: Colors.transparent,
      strokeWidth: 2.5,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      headerBackgroundColor: AppColors.ink,
      headerForegroundColor: AppColors.onInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      dialHandColor: AppColors.ink,
      dialBackgroundColor: AppColors.sunk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(Radii.xl)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      textStyle: TextStyle(color: AppColors.onInk, fontSize: 12),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.ink,
      selectionColor: AppColors.sunkStrong,
      selectionHandleColor: AppColors.ink,
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
