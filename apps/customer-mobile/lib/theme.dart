import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sydney CBD fallback coordinates (used when auto-location is unavailable).
const double kSydneyLat = -33.8688;
const double kSydneyLng = 151.2093;

/// Grocery-Mart customer design system — "Spice Market": a warm, light, food-forward
/// look inspired by modern delivery apps. Cream paper, saffron-coral primary, fresh-green
/// deal accents, an editorial serif (Fraunces) paired with a friendly grotesque (Plus Jakarta Sans).
/// Field names are kept stable so every screen inherits the new palette automatically.
class Gm {
  Gm._();

  // Surfaces
  static const Color bg0 = Color(0xFFFFF6EC); // warm cream paper (scaffold)
  static const Color bg1 = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);

  // Ink
  static const Color text = Color(0xFF221A12); // warm near-black
  static const Color textDim = Color(0xFF8C8175);

  // Brand
  static const Color accent = Color(0xFFF4511E); // saffron-coral primary
  static const Color accent2 = Color(0xFFFF8A3D); // warm amber (gradient partner)
  static const Color fresh = Color(0xFF0FA968); // deals / cheapest / free delivery
  static const Color star = Color(0xFFF6A609); // ratings
  static const Color danger = Color(0xFFE5484D);
  static const Color warn = Color(0xFFF6A609);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color line = Color(0xFFF0E6D8); // hairline borders

  static const double radius = 20;
  static const double radiusSm = 12;

  // Back-compat aliases used by existing screens (now light surfaces)
  static Color get glassFill => surface;
  static Color get glassFillStrong => const Color(0xFFFFFBF5);
  static Color get glassBorder => line;

  static List<Color> get heat => const [accent, accent2];

  /// Editorial display style (store names, section heads, the wordmark).
  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w700, Color color = text, double? height, double spacing = -0.3}) =>
      GoogleFonts.fraunces(
          fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  static ThemeData themeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: surface,
    ).copyWith(primary: accent, secondary: accent2, surface: surface);

    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, colorScheme: scheme);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: text, displayColor: text);

    return base.copyWith(
      scaffoldBackgroundColor: bg0,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAF3E9),
        hintStyle: const TextStyle(color: textDim),
        labelStyle: const TextStyle(color: textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
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
    const palettes = [
      [Color(0xFFFF8A3D), Color(0xFFF4511E)],
      [Color(0xFFFFC14D), Color(0xFFFF8A3D)],
      [Color(0xFF34D399), Color(0xFF0FA968)],
      [Color(0xFFFB7185), Color(0xFFE11D48)],
      [Color(0xFFA78BFA), Color(0xFF7C3AED)],
      [Color(0xFF38BDF8), Color(0xFF0E7490)],
      [Color(0xFFFCD34D), Color(0xFFF59E0B)],
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
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? Gm.glassFillStrong : Gm.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Gm.line),
        boxShadow: const [
          BoxShadow(color: Color(0x14B08A5A), blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    final clipped = ClipRRect(borderRadius: BorderRadius.circular(radius), child: card);
    return margin == null ? clipped : Padding(padding: margin!, child: clipped);
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
                        style: GoogleFonts.plusJakartaSans(
                            color: Gm.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
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
  const GmEmpty({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Gm.textDim, size: 40),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Gm.textDim)),
      ]),
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
