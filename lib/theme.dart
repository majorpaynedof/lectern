import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'state/theme_controller.dart' show TouchContext;

/// One complete color scheme for the app. Widgets read the active palette
/// with `context.colors`, so switching themes repaints everything.
@immutable
class LecternPalette extends ThemeExtension<LecternPalette> {
  const LecternPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.textSoft,
    required this.muted,
    required this.secondaryGlow,
    this.danger = const Color(0xFFFF7A7A),
    this.group = 'Classic',
    this.sidebar,
  });

  final String id;
  final String name;
  final String group; // section on the Appearance page
  final Color? sidebar; // exact jersey color for the sidebar and player bar (team themes)
  final Brightness brightness;

  final Color bg; // window background
  final Color surface; // sidebar, mini player, cards
  final Color surfaceHigh; // inputs, menus, raised bits
  final Color border;
  final Color accent; // buttons, progress, highlights
  final Color onAccent; // text/icons on top of accent
  final Color text;
  final Color textSoft; // descriptions, secondary lines
  final Color muted; // captions, metadata
  final Color secondaryGlow; // second blob on the sign-in screen
  final Color danger;

  // Derived colors, so presets only need the basics above.
  Color get accentSoft => accent.withAlpha(38);
  Color get hover => text.withAlpha(16);
  Color get track => text.withAlpha(48);
  Color get accentLight => Color.lerp(accent, Colors.white, 0.3)!;

  Color get sidebarColor => sidebar ?? surface;

  /// The palette to use *on* the sidebar and player bar. For team themes the
  /// sidebar is the exact jersey color, so text switches to dark or white
  /// (whichever reads better), and the accent falls back to that text color
  /// if it would blend into the jersey.
  LecternPalette forSidebar() {
    final s = sidebar;
    if (s == null) return this;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }
    const darkInk = Color(0xFF15171C);
    final fg = contrast(darkInk, s) > contrast(Colors.white, s) ? darkInk : Colors.white;
    final acc = contrast(accent, s) >= 2.5 ? accent : fg;
    return LecternPalette(
      id: id,
      name: name,
      group: group,
      brightness: fg == darkInk ? Brightness.light : Brightness.dark,
      bg: s,
      surface: s,
      surfaceHigh: Color.lerp(s, fg, 0.10)!,
      border: Color.lerp(s, fg, 0.18)!,
      accent: acc,
      onAccent: acc.computeLuminance() > 0.4 ? const Color(0xFF111111) : Colors.white,
      text: fg,
      textSoft: fg.withAlpha(225),
      muted: fg.withAlpha(175),
      secondaryGlow: secondaryGlow,
      danger: danger,
    );
  }

  @override
  LecternPalette copyWith() => this;

  @override
  LecternPalette lerp(ThemeExtension<LecternPalette>? other, double t) {
    if (other is! LecternPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LecternPalette(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      group: t < 0.5 ? group : other.group,
      sidebar: sidebar == null && other.sidebar == null ? null : Color.lerp(sidebarColor, other.sidebarColor, t),
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      border: l(border, other.border),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      text: l(text, other.text),
      textSoft: l(textSoft, other.textSoft),
      muted: l(muted, other.muted),
      secondaryGlow: l(secondaryGlow, other.secondaryGlow),
      danger: l(danger, other.danger),
    );
  }
}

extension LecternColors on BuildContext {
  LecternPalette get colors => Theme.of(this).extension<LecternPalette>() ?? LecternPalettes.all.first;
}

/// The built-in color combinations. Add a new one here and it shows up
/// on the Appearance page automatically.
class LecternPalettes {
  static const amber = LecternPalette(
    id: 'amber',
    name: 'Amber',
    brightness: Brightness.dark,
    bg: Color(0xFF0E0F13),
    surface: Color(0xFF16181E),
    surfaceHigh: Color(0xFF1F222B),
    border: Color(0xFF2A2E38),
    accent: Color(0xFFF0A35E),
    onAccent: Color(0xFF1C1206),
    text: Color(0xFFECEDEF),
    textSoft: Color(0xFFC9CDD4),
    muted: Color(0xFF8E95A2),
    secondaryGlow: Color(0xFF7A5CFF),
  );

  static const midnight = LecternPalette(
    id: 'midnight',
    name: 'Midnight',
    brightness: Brightness.dark,
    bg: Color(0xFF0B1020),
    surface: Color(0xFF121A2E),
    surfaceHigh: Color(0xFF1A2440),
    border: Color(0xFF26324F),
    accent: Color(0xFF6EA8FF),
    onAccent: Color(0xFF06142B),
    text: Color(0xFFE8EEFA),
    textSoft: Color(0xFFC3CDE3),
    muted: Color(0xFF8592AE),
    secondaryGlow: Color(0xFFB06EFF),
  );

  static const forest = LecternPalette(
    id: 'forest',
    name: 'Forest',
    brightness: Brightness.dark,
    bg: Color(0xFF0C1210),
    surface: Color(0xFF121A17),
    surfaceHigh: Color(0xFF1A2520),
    border: Color(0xFF26342D),
    accent: Color(0xFF6FCF97),
    onAccent: Color(0xFF07190F),
    text: Color(0xFFE7F0EB),
    textSoft: Color(0xFFC2D1C8),
    muted: Color(0xFF86978D),
    secondaryGlow: Color(0xFF3FB8C9),
  );

  static const rose = LecternPalette(
    id: 'rose',
    name: 'Rosé',
    brightness: Brightness.dark,
    bg: Color(0xFF140E12),
    surface: Color(0xFF1C1419),
    surfaceHigh: Color(0xFF261B22),
    border: Color(0xFF36262F),
    accent: Color(0xFFF28AB2),
    onAccent: Color(0xFF2A0A18),
    text: Color(0xFFF3E9EE),
    textSoft: Color(0xFFD9C6CF),
    muted: Color(0xFF9E8892),
    secondaryGlow: Color(0xFFFFB37A),
  );

  static const arctic = LecternPalette(
    id: 'arctic',
    name: 'Arctic',
    brightness: Brightness.dark,
    bg: Color(0xFF2E3440),
    surface: Color(0xFF3B4252),
    surfaceHigh: Color(0xFF434C5E),
    border: Color(0xFF4C566A),
    accent: Color(0xFF88C0D0),
    onAccent: Color(0xFF1F2A33),
    text: Color(0xFFECEFF4),
    textSoft: Color(0xFFD8DEE9),
    muted: Color(0xFFA3ABB9),
    secondaryGlow: Color(0xFFB48EAD),
  );

  static const oled = LecternPalette(
    id: 'oled',
    name: 'Pure black',
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface: Color(0xFF0B0B0B),
    surfaceHigh: Color(0xFF181818),
    border: Color(0xFF262626),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
    text: Color(0xFFF2F2F2),
    textSoft: Color(0xFFC8C8C8),
    muted: Color(0xFF8A8A8A),
    secondaryGlow: Color(0xFF7A7A7A),
  );

  static const paper = LecternPalette(
    id: 'paper',
    name: 'Paper',
    brightness: Brightness.light,
    bg: Color(0xFFF6F3EE),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFEAE2),
    border: Color(0xFFE0D9CE),
    accent: Color(0xFFC8642B),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF1F1B16),
    textSoft: Color(0xFF4A443C),
    muted: Color(0xFF857D72),
    secondaryGlow: Color(0xFF7A5CFF),
    danger: Color(0xFFC0392B),
  );

  static const sky = LecternPalette(
    id: 'sky',
    name: 'Daylight',
    brightness: Brightness.light,
    bg: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE8EDF4),
    border: Color(0xFFD7DFEA),
    accent: Color(0xFF2F6FEB),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF141A24),
    textSoft: Color(0xFF3D4757),
    muted: Color(0xFF7A8597),
    secondaryGlow: Color(0xFF16B3A0),
    danger: Color(0xFFC0392B),
  );


  // Team-color themes. Original names only: no team names, cities,
  // mascots or logos (those are trademarks).
  static final football = [
    _team('Football Inspired', 'royal-flare', 'Royal Flare', 0xFF00338D, 0xFFC60C30),
    _team('Football Inspired', 'reef-sunset', 'Reef Sunset', 0xFF008E97, 0xFFFC4C02),
    _team('Football Inspired', 'harbor-navy', 'Harbor Navy', 0xFF002244, 0xFFC60C30),
    _team('Football Inspired', 'meadow-green', 'Meadow Green', 0xFF125740, 0xFFFFFFFF),
    _team('Football Inspired', 'midnight-plum', 'Midnight Plum', 0xFF241773, 0xFF9E7C0C),
    _team('Football Inspired', 'blaze-orange', 'Blaze Orange', 0xFF000000, 0xFFFB4F14),
    _team('Football Inspired', 'autumn-leather', 'Autumn Leather', 0xFF311D00, 0xFFFF3C00),
    _team('Football Inspired', 'night-gold', 'Night Gold', 0xFF101820, 0xFFFFB612),
    _team('Football Inspired', 'crimson-night', 'Crimson Night', 0xFF03202F, 0xFFA71930),
    _team('Football Inspired', 'prairie-blue', 'Prairie Blue', 0xFF002C5F, 0xFFA2AAAD),
    _team('Football Inspired', 'riverside-teal', 'Riverside Teal', 0xFF006778, 0xFFD7A22A),
    _team('Football Inspired', 'glacier-blue', 'Glacier Blue', 0xFF4B92DB, 0xFFC8102E),
    _team('Football Inspired', 'summit-orange', 'Summit Orange', 0xFFFB4F14, 0xFFFFFFFF),
    _team('Football Inspired', 'prairie-fire', 'Prairie Fire', 0xFFE31837, 0xFFFFB81C),
    _team('Football Inspired', 'silver-shadow', 'Silver Shadow', 0xFF000000, 0xFFA5ACAF),
    _team('Football Inspired', 'powder-sky', 'Powder Sky', 0xFF0080C6, 0xFFFFC20E),
    _teamLight('Football Inspired', 'frontier-silver', 'Frontier Silver', 0xFF041E42, 0xFF869397),
    _team('Football Inspired', 'metro-blue', 'Metro Blue', 0xFF0B2265, 0xFFA71930),
    _team('Football Inspired', 'pine-silver', 'Pine Silver', 0xFF004C54, 0xFFA5ACAF),
    _team('Football Inspired', 'burgundy-gold', 'Burgundy Gold', 0xFF5A1414, 0xFFFFB612),
    _team('Football Inspired', 'navy-flame', 'Navy Flame', 0xFF0B162A, 0xFFC83803),
    _team('Football Inspired', 'lagoon-blue', 'Lagoon Blue', 0xFF0076B6, 0xFFB0B7BC),
    _team('Football Inspired', 'evergreen-gold', 'Evergreen Gold', 0xFF203731, 0xFFFFB612),
    _team('Football Inspired', 'aurora-purple', 'Aurora Purple', 0xFF4F2683, 0xFFFFC62F),
    _team('Football Inspired', 'scarlet-night', 'Scarlet Night', 0xFFA71930, 0xFFFFFFFF),
    _team('Football Inspired', 'electric-blue', 'Electric Blue', 0xFF101820, 0xFF0085CA),
    _team('Football Inspired', 'antique-gold', 'Antique Gold', 0xFF101820, 0xFFD3BC8D),
    _team('Football Inspired', 'pewter-red', 'Pewter Red', 0xFFD50A0A, 0xFFB1BABF),
    _team('Football Inspired', 'desert-red', 'Desert Red', 0xFF97233F, 0xFFFFFFFF),
    _team('Football Inspired', 'royal-sun', 'Royal Sun', 0xFF003594, 0xFFFFD100),
    _team('Football Inspired', 'crimson-gold', 'Crimson Gold', 0xFFAA0000, 0xFFB3995D),
    _team('Football Inspired', 'neon-moss', 'Neon Moss', 0xFF002244, 0xFF69BE28),
  ];

  static final hockey = [
    _team('Hockey Inspired', 'red-steel', 'Red Steel', 0xFFC8102E, 0xFFA2AAAD),
    _team('Hockey Inspired', 'midnight-silver', 'Midnight Red', 0xFF041E42, 0xFFC8102E),
    _team('Hockey Inspired', 'black-cherry', 'Black Cherry', 0xFFC8102E, 0xFFFFFFFF),
    _team('Hockey Inspired', 'coastline-orange', 'Coastline Orange', 0xFF003087, 0xFFFC4C02),
    _team('Hockey Inspired', 'cobalt-red', 'Cobalt Red', 0xFF0033A0, 0xFFC8102E),
    _team('Hockey Inspired', 'burnt-orange', 'Burnt Orange', 0xFFCF4520, 0xFFFFFFFF),
    _team('Hockey Inspired', 'gilded-black', 'Gilded Black', 0xFF000000, 0xFFFFB81C),
    _team('Hockey Inspired', 'starboard-red', 'Starboard Red', 0xFFC8102E, 0xFF041E42),
    _team('Hockey Inspired', 'honey-black', 'Honey Black', 0xFF000000, 0xFFFFB81C),
    _team('Hockey Inspired', 'royal-gold', 'Royal Gold', 0xFF003087, 0xFFFFB81C),
    _team('Hockey Inspired', 'cherry-frost', 'Cherry Frost', 0xFFC8102E, 0xFFFFFFFF),
    _team('Hockey Inspired', 'red-brass', 'Red Brass', 0xFFC8102E, 0xFFB9975B),
    _team('Hockey Inspired', 'velvet-red', 'Velvet Red', 0xFFA6192E, 0xFF001E62),
    _team('Hockey Inspired', 'antique-brass', 'Black Crimson', 0xFF000000, 0xFFC8102E),
    _team('Hockey Inspired', 'deep-navy', 'Deep Navy', 0xFF00205B, 0xFFFFFFFF),
    _team('Hockey Inspired', 'frost-navy', 'Frost Navy', 0xFF00205B, 0xFFFFFFFF),
    _team('Hockey Inspired', 'crimson-ink', 'Crimson Ink', 0xFFC8102E, 0xFFFFFFFF),
    _team('Hockey Inspired', 'merlot-blue', 'Merlot Blue', 0xFF6F263D, 0xFF236192),
    _team('Hockey Inspired', 'emerald-silver', 'Emerald Silver', 0xFF00843D, 0xFFA2AAAD),
    _team('Hockey Inspired', 'pine-gold', 'Pine Wheat', 0xFF154734, 0xFFDDCBA4),
    _team('Hockey Inspired', 'navy-gold', 'Marigold', 0xFFFFB81C, 0xFFFFFFFF),
    _team('Hockey Inspired', 'sapphire-gold', 'Sapphire Gold', 0xFF0072CE, 0xFFFFB81C),
    _team('Hockey Inspired', 'sky-black', 'Sky Black', 0xFF000000, 0xFF6CACE4),
    _team('Hockey Inspired', 'polar-blue', 'Polar Blue', 0xFF041E42, 0xFF004C97),
    _team('Hockey Inspired', 'copper-gold', 'Copper Gold', 0xFFCF4520, 0xFF89734C),
    _team('Hockey Inspired', 'saffron-red', 'Saffron Red', 0xFFC8102E, 0xFFF1BE48),
    _team('Hockey Inspired', 'navy-copper', 'Navy Copper', 0xFFCF4520, 0xFF00205B),
    _team('Hockey Inspired', 'graphite-silver', 'Graphite Silver', 0xFF000000, 0xFFA2AAAD),
    _team('Hockey Inspired', 'tidepool-orange', 'Tidepool Orange', 0xFF006272, 0xFFE57200),
    _team('Hockey Inspired', 'seaglass', 'Seaglass', 0xFF051C2C, 0xFF9CDBD9),
    _team('Hockey Inspired', 'cedar-blue', 'Cedar Blue', 0xFF00205B, 0xFF00843D),
    _team('Hockey Inspired', 'brass-steel', 'Brass Steel', 0xFFC69214, 0xFFC8102E),
  ];

  static final all = <LecternPalette>[amber, midnight, forest, rose, arctic, oled, paper, sky, ...football, ...hockey];

  static LecternPalette byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return amber;
  }
}

ThemeData buildTheme(LecternPalette p, {bool touch = false}) {
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.textSoft,
    error: p.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final radius = BorderRadius.circular(12);

  return base.copyWith(
    extensions: [p],
    // Touch mode: roomier controls and finger-sized tap targets.
    visualDensity: touch ? VisualDensity.standard : VisualDensity.compact,
    materialTapTargetSize: touch ? MaterialTapTargetSize.padded : MaterialTapTargetSize.shrinkWrap,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: touch ? const Size(52, 52) : const Size(40, 40),
        iconSize: touch ? 28 : 24,
      ),
    ),
    scaffoldBackgroundColor: p.bg,
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.text),
    dividerColor: p.border,
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: p.accent,
      inactiveTrackColor: p.track,
      thumbColor: p.brightness == Brightness.dark ? Colors.white : p.accent,
      overlayColor: p.hover,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.accent)),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHigh,
      textStyle: TextStyle(color: p.text),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(p.text.withAlpha(68)),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(touch ? 10 : 6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: p.text, fontSize: 12),
    ),
  );
}

/// Builds a dark theme from a team's main color (tints the backgrounds)
/// and second color (buttons and highlights).
LecternPalette _team(String group, String id, String name, int baseHex, int accentHex) {
  final base = Color(baseHex);
  var accent = Color(accentHex);
  // Very dark accents disappear on a dark background, so lift them a bit.
  if (accent.computeLuminance() < 0.08) accent = Color.lerp(accent, Colors.white, 0.25)!;
  // Keep the team color's hue, but at fixed dark brightness levels, so
  // every theme is equally readable and clearly shows its team color.
  final hsl = HSLColor.fromColor(base);
  // A real gray (like steel or pewter) is the team's look, so keep its tone
  // and use lighter levels; otherwise it would just turn black.
  final isGray = hsl.saturation < 0.35 && hsl.lightness > 0.12;
  Color shade(double lightness, double saturationScale) => hsl
      .withLightness(lightness)
      .withSaturation(isGray ? hsl.saturation : (hsl.saturation * saturationScale).clamp(0.0, 1.0))
      .toColor();
  return LecternPalette(
    id: id,
    name: name,
    group: group,
    brightness: Brightness.dark,
    bg: shade(isGray ? 0.10 : 0.09, 0.80),
    // The sidebar and player bar wear the exact home-jersey color.
    sidebar: base,
    surface: shade(isGray ? 0.16 : 0.13, 0.75),
    surfaceHigh: shade(isGray ? 0.21 : 0.17, 0.80),
    border: shade(isGray ? 0.28 : 0.26, 0.80),
    accent: accent,
    onAccent: accent.computeLuminance() > 0.4 ? const Color(0xFF111111) : Colors.white,
    text: const Color(0xFFECEDEF),
    textSoft: const Color(0xFFC9CDD4),
    muted: const Color(0xFFA9B0BB), // a bit lighter so it reads on colored sidebars
    secondaryGlow: Color.lerp(base, Colors.white, 0.15)!,
  );
}

/// Light theme for a team whose home jersey is white: white backgrounds,
/// with the team's dark color for buttons and text.
LecternPalette _teamLight(String group, String id, String name, int darkHex, int secondHex) {
  final dark = Color(darkHex);
  Color tint(double amount) => Color.lerp(Colors.white, dark, amount)!;
  return LecternPalette(
    id: id,
    name: name,
    group: group,
    brightness: Brightness.light,
    bg: tint(0.04),
    surface: Colors.white,
    surfaceHigh: tint(0.08),
    border: tint(0.16),
    accent: dark,
    onAccent: Colors.white,
    text: Color.lerp(dark, Colors.black, 0.35)!,
    textSoft: tint(0.80),
    muted: Color(secondHex),
    secondaryGlow: Color(secondHex),
    danger: const Color(0xFFC0392B),
  );
}

/// Applies the sidebar version of the current palette to its child, so the
/// sidebar and player bar can wear the jersey color with readable text.
class SidebarTheme extends StatelessWidget {
  const SidebarTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: buildTheme(context.colors.forSidebar(), touch: context.isTouch), child: child);
}
