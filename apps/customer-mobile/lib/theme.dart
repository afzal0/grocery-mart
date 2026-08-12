import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Sydney CBD fallback coordinates (used when auto-location is unavailable).
const double kSydneyLat = -33.8688;
const double kSydneyLng = 151.2093;

/// Grocery-Mart customer design system.
///
/// Light-first and Apple-flavoured, mirroring `packages/design-tokens/gm-light.css` so the
/// customer app and the two web portals read as one product: near-white ground, white
/// surfaces, hairline borders, soft radii, a single restrained green accent.
///
/// Typography is the PLATFORM font (SF Pro on iOS, Roboto on Android) rather than a webfont
/// pair — that is what an Apple-native surface uses, and it removes a network fetch from
/// first paint. Field names are unchanged so every screen inherits the palette for free.
class Gm {
  Gm._();

  // Surfaces
  static const Color bg0 = Color(0xFFF7F8F8); // page ground
  static const Color bg1 = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSunk = Color(0xFFFAFBFB); // inset rows, sheet grabbers

  // Ink — neutrals carry a slight green bias so they sit with the accent, not under it
  static const Color text = Color(0xFF0F1A17);
  static const Color textDim = Color(0xFF5B6B66);
  static const Color textFaint = Color(0xFF8A9793);

  // Brand
  static const Color accent = Color(0xFF059669); // grocery green, matches the shop portal
  static const Color accent2 = Color(0xFF10B981); // lighter partner for gradients
  static const Color fresh = Color(0xFF047857); // credits, in-stock, positive money
  static const Color star = Color(0xFFB45309); // ratings
  static const Color danger = Color(0xFFB91C1C);
  static const Color warn = Color(0xFFB45309);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color line = Color(0x170F1A17); // ~9% hairline
  static const Color lineSoft = Color(0x0D0F1A17); // ~5% hairline

  static const double radius = 12;
  static const double radiusSm = 8;

  // Back-compat aliases still referenced by some screens.
  static Color get glassFill => surface;
  static Color get glassFillStrong => surfaceSunk;
  static Color get glassBorder => line;

  static List<Color> get heat => const [accent, accent2];

  /// Display style for titles and section heads. Platform font, tightened tracking at
  /// larger sizes the way SF Pro Display does.
  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600, Color color = text, double? height, double spacing = -0.4}) =>
      TextStyle(
          fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  /// Tabular figures — prices and totals must not jitter as digits change.
  static TextStyle money(double size, {FontWeight weight = FontWeight.w600, Color color = text}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: surface,
    ).copyWith(primary: accent, secondary: accent2, surface: surface);

    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, colorScheme: scheme);
    final textTheme = base.textTheme.apply(bodyColor: text, displayColor: text);

    return base.copyWith(
      scaffoldBackgroundColor: bg0,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSunk,
        hintStyle: const TextStyle(color: textDim),
        labelStyle: const TextStyle(color: textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- Cuisine identity (tint, accent, emoji) -------------------------------------------
  static const Map<String, (Color, Color, String)> _cuisine = {
    'indian': (Color(0xFFFFE9D6), Color(0xFFC2410C), '🍛'),
    'pakistani': (Color(0xFFE3F5E9), Color(0xFF15803D), '🥘'),
    'bengali': (Color(0xFFFCE9F0), Color(0xFFBE185D), '🐟'),
    'srilankan': (Color(0xFFFFF1CF), Color(0xFFB45309), '🥥'),
    'afghan': (Color(0xFFEDE7FE), Color(0xFF6D28D9), '🫓'),
    'nepali': (Color(0xFFE2F2FA), Color(0xFF0E7490), '🍜'),
  };

  static (Color, Color, String) cuisine(String? c) =>
      _cuisine[c?.toLowerCase()] ?? const (Color(0xFFF1ECE3), Color(0xFF6B5E4E), '🛒');

  static String cuisineLabel(String c) => switch (c.toLowerCase()) {
        'srilankan' => 'Sri Lankan',
        _ => c.isEmpty ? c : c[0].toUpperCase() + c.substring(1),
      };

  /// Deterministic warm gradient for a store/product "photo" header.
  static List<Color> imageGradient(String seed) {
    // Muted, low-chroma tints: these sit behind product names as placeholder "photography",
    // so they must never out-shout the price or the add button.
    const palettes = [
      [Color(0xFFE8F1EE), Color(0xFFD7E8E1)],
      [Color(0xFFEDEFE9), Color(0xFFDFE4DA)],
      [Color(0xFFEAF0F3), Color(0xFFD9E4EA)],
      [Color(0xFFF2EDE8), Color(0xFFE6DCD2)],
      [Color(0xFFECEEF4), Color(0xFFDCE0EB)],
      [Color(0xFFEFEDF2), Color(0xFFE1DDE8)],
      [Color(0xFFE9F0EA), Color(0xFFD8E5DA)],
    ];
    var h = 0;
    for (final ch in seed.codeUnits) {
      h = (h * 31 + ch) & 0x7fffffff;
    }
    return palettes[h % palettes.length];
  }
}

/// Soft warm page background (mostly cream with a faint top glow).
class GmBackground extends StatelessWidget {
  const GmBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF1E2), Gm.bg0],
          stops: [0.0, 0.34],
        ),
      ),
      child: child,
    );
  }
}

/// Clean white card with a soft shadow and hairline border (the new "surface").
class GmGlass extends StatelessWidget {
  const GmGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Gm.radius,
    this.strong = false,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    // Only build a Material/InkWell when the card is actually tappable — a large disabled
    // InkWell ink surface renders as an opaque grey rectangle on the web (CanvasKit).
    final Widget inner = onTap == null
        ? Padding(padding: padding, child: child)
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          );
    final card = Container(
      decoration: BoxDecoration(
        color: strong ? Gm.glassFillStrong : Gm.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Gm.line),
        boxShadow: const [
          BoxShadow(color: Color(0x14B08A5A), blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// Primary saffron gradient button with white label.
class GmButton extends StatelessWidget {
  const GmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = true,
    this.gradient = const [Gm.accent, Gm.accent2],
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool expand;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || onPressed == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(Gm.radiusSm),
          boxShadow: [
            BoxShadow(color: gradient.last.withValues(alpha: 0.34), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Gm.radiusSm),
            onTap: disabled ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Gm.onPrimary))
                  else if (icon != null) ...[
                    Icon(icon, size: 18, color: Gm.onPrimary),
                    const SizedBox(width: 8),
                  ],
                  if (!busy)
                    Text(label,
                        style: const TextStyle(
                            color: Gm.onPrimary, fontWeight: FontWeight.w600, fontSize: 15,
                            letterSpacing: -0.1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outline / ghost button.
class GmGhostButton extends StatelessWidget {
  const GmGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = Gm.accent,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || onPressed == null;
    return OutlinedButton.icon(
      onPressed: disabled ? null : onPressed,
      icon: busy
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : (icon != null ? Icon(icon, size: 18, color: color) : const SizedBox.shrink()),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gm.radiusSm)),
      ),
    );
  }
}

class GmGradientText extends StatelessWidget {
  const GmGradientText(this.text,
      {super.key, this.style, this.textAlign, this.colors = const [Gm.accent, Gm.accent2]});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (b) => LinearGradient(colors: colors).createShader(b),
      child: Text(text, textAlign: textAlign, style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
    );
  }
}

/// Soft tinted badge pill.
class GmBadge extends StatelessWidget {
  const GmBadge(this.label, {super.key, this.color = Gm.accent, this.icon, this.solid = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: solid ? null : Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// ★ rating pill used on cards.
class GmRatingPill extends StatelessWidget {
  const GmRatingPill(this.rating, {super.key, this.count, this.compact = false});
  final num? rating;
  final int? count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rating == null) {
      return const Text('New', style: TextStyle(color: Gm.fresh, fontWeight: FontWeight.w700, fontSize: 12.5));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: Gm.star),
      const SizedBox(width: 3),
      Text(rating!.toStringAsFixed(1),
          style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w800, fontSize: 13)),
      if (!compact && count != null) ...[
        const SizedBox(width: 3),
        Text('($count)', style: const TextStyle(color: Gm.textDim, fontSize: 12)),
      ],
    ]);
  }
}

class GmLoading extends StatelessWidget {
  const GmLoading({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Gm.accent),
        if (label != null) ...[const SizedBox(height: 14), Text(label!, style: const TextStyle(color: Gm.textDim))],
      ]),
    );
  }
}

class GmError extends StatelessWidget {
  const GmError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: GmGlass(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Gm.danger, size: 34),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Gm.text)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GmGhostButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
          ],
        ]),
      ),
    );
  }
}

class GmEmpty extends StatelessWidget {
  const GmEmpty({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.icon = Icons.inbox_outlined,
  });

  final String message;

  /// Optional headline. An empty state that only explains the absence leaves the user
  /// with nothing to do, so [action] can offer the way out.
  final String? title;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Gm.textFaint, size: 36),
          const SizedBox(height: 14),
          if (title != null) ...[
            Text(title!, textAlign: TextAlign.center, style: Gm.display(16)),
            const SizedBox(height: 6),
          ],
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gm.textDim, fontSize: 14, height: 1.45)),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ]),
      ),
    );
  }
}

class GmUi {
  GmUi._();

  static void snack(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? const Color(0xFFFFB4A8) : const Color(0xFF7BE3B2), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ]),
      ));
  }

  static String money(num? amount, [String currency = 'AUD']) {
    if (amount == null) return '—';
    final symbol = currency == 'AUD' ? r'$' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  static String distance(num? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// Rough delivery ETA window from distance, for display.
  static String eta(num? meters) {
    final km = (meters ?? 0) / 1000;
    final lo = (12 + km * 1.6).round();
    return '$lo–${lo + 12} min';
  }

  static (String, Color) statusChip(String? status) {
    switch (status) {
      case 'delivered':
        return ('Delivered', Gm.fresh);
      case 'on_the_way':
        return ('On the way', Gm.accent);
      case 'processing':
        return ('Processing', Gm.warn);
      case 'cancelled':
        return ('Cancelled', Gm.danger);
      case 'pending':
      default:
        return (_titleize(status ?? 'pending'), Gm.textDim);
    }
  }

  static (String, Color) paymentChip(String? p) {
    switch (p) {
      case 'paid':
        return ('Paid', Gm.fresh);
      case 'refunded':
        return ('Refunded', Gm.accent);
      case 'pending_payment':
      default:
        return ('Payment due', Gm.warn);
    }
  }

  static String _titleize(String s) => s.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  static String titleize(String s) => _titleize(s);
}
