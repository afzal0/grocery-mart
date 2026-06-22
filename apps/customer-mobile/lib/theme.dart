import 'dart:ui';

import 'package:flutter/material.dart';

/// Liquid Glass design tokens for the customer app.
/// Mirrors packages/design-tokens/liquid-glass.css.
class Gm {
  Gm._();

  static const Color bg0 = Color(0xFF070B16);
  static const Color bg1 = Color(0xFF111A30);
  static const Color accent = Color(0xFF34D399); // emerald
  static const Color accent2 = Color(0xFF22D3EE); // cyan
  static const Color text = Color(0xFFEAF1FF);
  static const Color textDim = Color(0xFF9DB0D4);
  static const Color danger = Color(0xFFF87171);
  static const Color warn = Color(0xFFFBBF24);

  static const double radius = 22;
  static const double radiusSm = 12;

  static Color get glassFill => Colors.white.withValues(alpha: 0.06);
  static Color get glassFillStrong => Colors.white.withValues(alpha: 0.10);
  static Color get glassBorder => Colors.white.withValues(alpha: 0.14);

  static ThemeData themeData() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: bg1,
      ).copyWith(primary: accent, secondary: accent2),
      scaffoldBackgroundColor: bg0,
      fontFamily: 'SF Pro Display',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintStyle: const TextStyle(color: textDim),
        labelStyle: const TextStyle(color: textDim),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bg1,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Full-screen dark gradient background used by every page.
class GmBackground extends StatelessWidget {
  const GmBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Gm.bg0, Color(0xFF0C1424), Gm.bg1],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted glass surface (BackdropFilter + translucent fill + thin border).
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
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: strong ? Gm.glassFillStrong : Gm.glassFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Gm.glassBorder),
          ),
          child: child,
        ),
      ),
    );
    final wrapped = onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: content,
            ),
          );
    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}

/// Gradient primary button. Shows a spinner + disables itself while [busy].
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
    final btn = Opacity(
      opacity: disabled ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(Gm.radiusSm),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Gm.radiusSm),
            onTap: disabled ? null : onPressed,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF06281C)),
                    )
                  else if (icon != null) ...[
                    Icon(icon, size: 18, color: const Color(0xFF06281C)),
                    const SizedBox(width: 8),
                  ],
                  if (!busy)
                    Text(label,
                        style: const TextStyle(
                            color: Color(0xFF06281C),
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return btn;
  }
}

/// Outline / ghost button on glass.
class GmGhostButton extends StatelessWidget {
  const GmGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = Gm.text,
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
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : (icon != null ? Icon(icon, size: 18, color: color) : const SizedBox.shrink()),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Gm.glassBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gm.radiusSm)),
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
      child: Text(text,
          textAlign: textAlign,
          style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
    );
  }
}

/// Small status / category badge pill.
class GmBadge extends StatelessWidget {
  const GmBadge(this.label, {super.key, this.color = Gm.accent, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Centered loading spinner.
class GmLoading extends StatelessWidget {
  const GmLoading({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Gm.accent),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(color: Gm.textDim)),
          ],
        ],
      ),
    );
  }
}

/// Error panel showing the problem+json detail, with optional retry.
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Gm.danger, size: 34),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Gm.text)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              GmGhostButton(
                  label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly empty state.
class GmEmpty extends StatelessWidget {
  const GmEmpty({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Gm.textDim, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gm.textDim)),
        ],
      ),
    );
  }
}

/// Helpers shared across screens.
class GmUi {
  GmUi._();

  static void snack(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? Gm.danger : Gm.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
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

  /// Maps order status -> friendly label + accent color.
  static (String, Color) statusChip(String? status) {
    switch (status) {
      case 'delivered':
        return ('Delivered', Gm.accent);
      case 'on_the_way':
        return ('On the way', Gm.accent2);
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
        return ('Paid', Gm.accent);
      case 'refunded':
        return ('Refunded', Gm.accent2);
      case 'pending_payment':
      default:
        return ('Payment due', Gm.warn);
    }
  }

  static String _titleize(String s) =>
      s.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  static String titleize(String s) => _titleize(s);
}
