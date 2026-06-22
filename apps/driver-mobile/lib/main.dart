import 'dart:ui';

import 'package:flutter/material.dart';

import 'api.dart';

// ---------------------------------------------------------------------------
// Theme tokens — Liquid Glass, dark/frosted, amber/orange driver accent.
// ---------------------------------------------------------------------------
const Color kBg0 = Color(0xFF0B0A07);
const Color kBg1 = Color(0xFF1B1505);
const Color kAccent = Color(0xFFFBBF24); // amber
const Color kAccent2 = Color(0xFFFB923C); // orange
const Color kText = Color(0xFFF7EFDD);
const Color kTextDim = Color(0xFFCBB890);
const Color kDanger = Color(0xFFF87171);
const Color kGood = Color(0xFF34D399);

void main() => runApp(const GroceryMartDriverApp());

class GroceryMartDriverApp extends StatelessWidget {
  const GroceryMartDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grocery-Mart Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg0,
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          secondary: kAccent2,
          surface: kBg1,
        ),
        fontFamily: 'SF Pro Display',
        textTheme: const TextTheme().apply(bodyColor: kText, displayColor: kText),
      ),
      home: const RootGate(),
    );
  }
}

/// Owns the single ApiClient and switches between the login screen and the
/// authenticated shell based on whether we hold a session.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  final ApiClient _api = ApiClient();

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _onSignedIn() => setState(() {});

  Future<void> _signOut() async {
    await _api.logout();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_api.isAuthenticated) {
      return LoginScreen(api: _api, onSignedIn: _onSignedIn);
    }
    return HomeShell(api: _api, onSignOut: _signOut);
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

/// Full-screen dark amber gradient background shared by every screen.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBg0, Color(0x33FBBF24), kBg1],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted translucent surface — the core Liquid Glass card.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// Gradient amber pill button with a busy spinner and disabled state.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.danger = false,
    this.subtle = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool danger;
  final bool subtle;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    final gradient = danger
        ? const LinearGradient(colors: [Color(0xFFF87171), Color(0xFFEF4444)])
        : const LinearGradient(colors: [kAccent, kAccent2]);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF2A1E03)),
          )
        else if (icon != null) ...[
          Icon(icon, size: 18, color: subtle ? kText : const Color(0xFF2A1E03)),
          const SizedBox(width: 8),
        ],
        if (!busy)
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: subtle ? kText : const Color(0xFF2A1E03),
            ),
          ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: subtle ? null : gradient,
              color: subtle ? Colors.white.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(14),
              border: subtle
                  ? Border.all(color: Colors.white.withValues(alpha: 0.16))
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: content,
          ),
        ),
      ),
    );
  }
}

class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.state});
  final JobState state;

  @override
  Widget build(BuildContext context) {
    late Color color;
    switch (state) {
      case JobState.assigned:
        color = kAccent;
        break;
      case JobState.accepted:
        color = kAccent2;
        break;
      case JobState.pickedUp:
        color = kGood;
        break;
      case JobState.unknown:
        color = kTextDim;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(state.label,
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: kTextDim),
            const SizedBox(width: 6),
          ],
          Text(label, style: const TextStyle(color: kTextDim, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Inline problem banner that surfaces the problem+json `detail`.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDanger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: kDanger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style:
                        const TextStyle(color: kDanger, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: kAccent),
                child: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: kTextDim.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextDim, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onSignedIn});
  final ApiClient api;
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.api.portalLogin(email, password);
      if (!session.isDriver) {
        // Role guard: only DRIVER accounts may use this app.
        await widget.api.logout();
        if (mounted) {
          setState(() => _error =
              'This account is not a driver. Drivers are provisioned by a shop (Shop portal → Drivers).');
        }
        return;
      }
      widget.onSignedIn();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [kAccent, kAccent2]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.local_shipping_rounded,
                              color: Color(0xFF2A1E03), size: 30),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                            colors: [kAccent, kAccent2]).createShader(b),
                        child: const Text(
                          'Grocery-Mart\nDriver',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                              letterSpacing: -0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in with the driver account your shop created for you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextDim, height: 1.4, fontSize: 13.5),
                      ),
                      const SizedBox(height: 22),
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],
                      _GlassField(
                        controller: _email,
                        hint: 'Email',
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_busy,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      _GlassField(
                        controller: _password,
                        hint: 'Password',
                        icon: Icons.lock_outline,
                        obscure: _obscure,
                        enabled: !_busy,
                        onSubmitted: (_) => _submit(),
                        trailing: IconButton(
                          icon: Icon(
                              _obscure ? Icons.visibility_off : Icons.visibility,
                              color: kTextDim,
                              size: 20),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlassButton(
                        label: 'Sign in',
                        busy: _busy,
                        icon: Icons.login_rounded,
                        onPressed: _busy ? null : _submit,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Endpoint: POST /auth/portal/login · role DRIVER required',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextDim, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.trailing,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(color: kText),
      cursorColor: kAccent,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextDim),
        prefixIcon: Icon(icon, color: kTextDim, size: 20),
        suffixIcon: trailing,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Authenticated shell (Jobs + Notifications tabs)
// ---------------------------------------------------------------------------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api, required this.onSignOut});
  final ApiClient api;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      JobsScreen(api: widget.api),
      NotificationsScreen(api: widget.api),
    ];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.local_shipping_rounded, color: kAccent, size: 22),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (b) =>
                  const LinearGradient(colors: [kAccent, kAccent2]).createShader(b),
              child: const Text('Driver',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.white, fontSize: 20)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, color: kTextDim),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kBg1,
                  title: const Text('Sign out?', style: TextStyle(color: kText)),
                  content: const Text('You will need to sign in again.',
                      style: TextStyle(color: kTextDim)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: kTextDim))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child:
                            const Text('Sign out', style: TextStyle(color: kAccent))),
                  ],
                ),
              );
              if (ok == true) await widget.onSignOut();
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: _GlassNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: kAccent.withValues(alpha: 0.18),
            selectedIndex: index,
            onDestinationSelected: onChanged,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined, color: kTextDim),
                selectedIcon: Icon(Icons.assignment, color: kAccent),
                label: 'Jobs',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_none, color: kTextDim),
                selectedIcon: Icon(Icons.notifications, color: kAccent),
                label: 'Alerts',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jobs list
// ---------------------------------------------------------------------------

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  late Future<List<DriverJob>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.jobs();
  }

  Future<void> _refresh() async {
    final f = widget.api.jobs();
    setState(() => _future = f);
    await f.catchError((_) => <DriverJob>[]);
  }

  Future<void> _openJob(DriverJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(api: widget.api, job: job),
      ),
    );
    // Returning from the detail may have changed state — refresh the list.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kAccent,
      backgroundColor: kBg1,
      onRefresh: _refresh,
      child: FutureBuilder<List<DriverJob>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _CenteredLoader(label: 'Loading your jobs…');
          }
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                ErrorBanner(
                  message: snap.error is ApiException
                      ? (snap.error as ApiException).detail
                      : '${snap.error}',
                  onRetry: _refresh,
                ),
              ],
            );
          }
          final jobs = snap.data ?? const <DriverJob>[];
          if (jobs.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No jobs right now',
                  subtitle:
                      'Assigned deliveries from your shop will appear here. Pull down to refresh.',
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _JobCard(job: jobs[i], onTap: () => _openJob(jobs[i])),
          );
        },
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onTap});
  final DriverJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #${job.orderId}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
              ),
              StateBadge(state: job.state),
            ],
          ),
          const SizedBox(height: 14),
          _Leg(icon: Icons.storefront_outlined, label: 'Pickup', value: job.pickupStore),
          const SizedBox(height: 10),
          _Leg(icon: Icons.flag_outlined, label: 'Drop-off', value: job.destination),
          const SizedBox(height: 14),
          Row(
            children: [
              Pill(
                  icon: job.timing == 'scheduled'
                      ? Icons.schedule
                      : Icons.bolt,
                  label: job.timing.isEmpty
                      ? 'timing —'
                      : job.timing[0].toUpperCase() + job.timing.substring(1)),
              const Spacer(),
              const Icon(Icons.chevron_right, color: kTextDim),
            ],
          ),
        ],
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: kAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: kTextDim,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      color: kText, fontSize: 14.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Job detail — state machine: assigned -> accepted -> picked_up -> delivered
// ---------------------------------------------------------------------------

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.api, required this.job});
  final ApiClient api;
  final DriverJob job;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late JobState _state;
  late String _rawState;
  bool _busy = false;
  String? _error;
  String? _info;

  // Location sharing state.
  bool _consent = false;
  bool _consentBusy = false;
  int _pingCount = 0;
  String? _lastPing;

  // Slowly-moving demo coordinate near the Sydney CBD. Each ping nudges it
  // a few metres toward the drop-off so tracking looks alive.
  static const double _baseLat = -33.8688;
  static const double _baseLng = 151.2093;
  double _demoLat = _baseLat;
  double _demoLng = _baseLng;

  @override
  void initState() {
    super.initState();
    _state = widget.job.state;
    _rawState = widget.job.rawState;
    _demoLat = _baseLat;
    _demoLng = _baseLng;
  }

  void _flash(String msg) => setState(() => _info = msg);

  Future<void> _run(Future<void> Function() action, {required String okMsg}) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted) _flash(okMsg);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() => _run(() async {
        await widget.api.acceptJob(widget.job.orderId);
        setState(() {
          _state = JobState.accepted;
          _rawState = 'accepted';
        });
      }, okMsg: 'Job accepted. Share your location, then mark pickup.');

  Future<void> _reject() async {
    await _run(() => widget.api.rejectJob(widget.job.orderId),
        okMsg: 'Job rejected.');
    if (mounted && _error == null) Navigator.of(context).pop();
  }

  Future<void> _pickup() => _run(() async {
        await widget.api.pickupJob(widget.job.orderId);
        setState(() {
          _state = JobState.pickedUp;
          _rawState = 'picked_up';
        });
      }, okMsg: 'Marked as picked up. Drive safe — then deliver.');

  Future<void> _deliver() async {
    await _run(() async {
      await widget.api.deliverJob(widget.job.orderId);
      setState(() {
        _state = JobState.unknown;
        _rawState = 'delivered';
      });
    }, okMsg: 'Delivered. Nice work!');
  }

  Future<void> _toggleConsent(bool value) async {
    setState(() {
      _consentBusy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.api.setConsent(widget.job.orderId, value);
      if (mounted) {
        setState(() {
          _consent = value;
          _info = value
              ? 'Location sharing on. Send a ping to update the customer.'
              : 'Location sharing off.';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _consentBusy = false);
    }
  }

  Future<void> _sendPing() async {
    // Nudge the demo coordinate toward the drop-off (or just drift) so the
    // location stream visibly moves between pings.
    final targetLat = widget.job.destLat ?? (_baseLat - 0.01);
    final targetLng = widget.job.destLng ?? (_baseLng + 0.01);
    _demoLat += (targetLat - _demoLat) * 0.12 + 0.0004;
    _demoLng += (targetLng - _demoLng) * 0.12 + 0.0004;
    final lat = double.parse(_demoLat.toStringAsFixed(6));
    final lng = double.parse(_demoLng.toStringAsFixed(6));
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.api.sendLocation(widget.job.orderId, lat, lng);
      if (mounted) {
        setState(() {
          _pingCount += 1;
          _lastPing = '$lat, $lng';
          _info = 'Location ping #$_pingCount sent.';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kText),
        title: Text('Order #${widget.job.orderId}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: kText)),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Status',
                            style: TextStyle(
                                color: kTextDim, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        StateBadge(state: _state),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Leg(
                        icon: Icons.storefront_outlined,
                        label: 'Pickup',
                        value: widget.job.pickupStore),
                    const SizedBox(height: 12),
                    _Leg(
                        icon: Icons.flag_outlined,
                        label: 'Drop-off',
                        value: widget.job.destination),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(
                            icon: widget.job.timing == 'scheduled'
                                ? Icons.schedule
                                : Icons.bolt,
                            label: widget.job.timing.isEmpty
                                ? 'timing —'
                                : widget.job.timing),
                        if (widget.job.destLat != null && widget.job.destLng != null)
                          Pill(
                              icon: Icons.place_outlined,
                              label:
                                  '${widget.job.destLat!.toStringAsFixed(4)}, ${widget.job.destLng!.toStringAsFixed(4)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: 14),
              ],
              if (_info != null) ...[
                _InfoBanner(message: _info!),
                const SizedBox(height: 14),
              ],
              _StateTimeline(state: _state, rawState: _rawState),
              const SizedBox(height: 14),
              ..._buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case JobState.assigned:
        return [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Respond to this job'),
                const SizedBox(height: 6),
                const Text(
                    'Accept to take the delivery, or reject to release it back to the shop.',
                    style: TextStyle(color: kTextDim, height: 1.4)),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Accept job',
                  icon: Icons.check_circle_outline,
                  busy: _busy,
                  onPressed: _busy ? null : _accept,
                ),
                const SizedBox(height: 10),
                GlassButton(
                  label: 'Reject',
                  icon: Icons.cancel_outlined,
                  danger: true,
                  subtle: true,
                  busy: false,
                  onPressed: _busy ? null : _reject,
                ),
              ],
            ),
          ),
        ];
      case JobState.accepted:
        return [
          _LocationCard(
            consent: _consent,
            consentBusy: _consentBusy,
            onConsentChanged: _busy ? null : _toggleConsent,
            pingCount: _pingCount,
            lastPing: _lastPing,
            onPing: (!_consent || _busy) ? null : _sendPing,
            pingBusy: _busy,
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('At the store'),
                const SizedBox(height: 6),
                const Text(
                    'Once you have collected the order, mark it as picked up.',
                    style: TextStyle(color: kTextDim, height: 1.4)),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Mark picked up',
                  icon: Icons.shopping_bag_outlined,
                  busy: _busy,
                  onPressed: _busy ? null : _pickup,
                ),
              ],
            ),
          ),
        ];
      case JobState.pickedUp:
        return [
          _LocationCard(
            consent: _consent,
            consentBusy: _consentBusy,
            onConsentChanged: _busy ? null : _toggleConsent,
            pingCount: _pingCount,
            lastPing: _lastPing,
            onPing: (!_consent || _busy) ? null : _sendPing,
            pingBusy: _busy,
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Complete the delivery'),
                const SizedBox(height: 6),
                const Text('Hand the order to the customer, then mark it delivered.',
                    style: TextStyle(color: kTextDim, height: 1.4)),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Mark delivered',
                  icon: Icons.task_alt,
                  busy: _busy,
                  onPressed: _busy ? null : _deliver,
                ),
              ],
            ),
          ),
        ];
      case JobState.unknown:
        // Either freshly delivered or an unrecognised server state.
        final delivered = _rawState == 'delivered';
        return [
          GlassCard(
            child: Column(
              children: [
                Icon(delivered ? Icons.celebration : Icons.help_outline,
                    size: 44, color: delivered ? kGood : kTextDim),
                const SizedBox(height: 12),
                Text(
                  delivered ? 'Delivered' : 'No actions available',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: kText),
                ),
                const SizedBox(height: 6),
                Text(
                  delivered
                      ? 'This order is complete. Head back to the jobs list for your next delivery.'
                      : 'This job is in state "$_rawState", which has no driver action in this app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kTextDim, height: 1.4),
                ),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Back to jobs',
                  icon: Icons.arrow_back,
                  subtle: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ];
    }
  }
}

class _StateTimeline extends StatelessWidget {
  const _StateTimeline({required this.state, required this.rawState});
  final JobState state;
  final String rawState;

  @override
  Widget build(BuildContext context) {
    final steps = ['Assigned', 'Accepted', 'Picked up', 'Delivered'];
    int activeIndex;
    switch (state) {
      case JobState.assigned:
        activeIndex = 0;
        break;
      case JobState.accepted:
        activeIndex = 1;
        break;
      case JobState.pickedUp:
        activeIndex = 2;
        break;
      case JobState.unknown:
        activeIndex = rawState == 'delivered' ? 3 : 0;
        break;
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = (i ~/ 2) < activeIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: done
                    ? kAccent.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            );
          }
          final idx = i ~/ 2;
          final reached = idx <= activeIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: reached
                      ? const LinearGradient(colors: [kAccent, kAccent2])
                      : null,
                  color: reached ? null : Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                      color: reached
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.18)),
                ),
                child: reached
                    ? const Icon(Icons.check, size: 14, color: Color(0xFF2A1E03))
                    : null,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 60,
                child: Text(
                  steps[idx],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: reached ? kText : kTextDim,
                      fontWeight: idx == activeIndex
                          ? FontWeight.w800
                          : FontWeight.w500),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.consent,
    required this.consentBusy,
    required this.onConsentChanged,
    required this.pingCount,
    required this.lastPing,
    required this.onPing,
    required this.pingBusy,
  });

  final bool consent;
  final bool consentBusy;
  final ValueChanged<bool>? onConsentChanged;
  final int pingCount;
  final String? lastPing;
  final VoidCallback? onPing;
  final bool pingBusy;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Live location'),
          const SizedBox(height: 6),
          const Text(
              'Share your location so the customer can track the delivery in real time.',
              style: TextStyle(color: kTextDim, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.my_location, size: 18, color: kAccent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Share my location',
                    style: TextStyle(color: kText, fontWeight: FontWeight.w600)),
              ),
              if (consentBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kAccent),
                )
              else
                Switch(
                  value: consent,
                  activeThumbColor: const Color(0xFF2A1E03),
                  activeTrackColor: kAccent,
                  onChanged: onConsentChanged,
                ),
            ],
          ),
          const Divider(height: 26, color: Color(0x22FFFFFF)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      consent
                          ? (pingCount == 0
                              ? 'No pings sent yet'
                              : '$pingCount ping${pingCount == 1 ? '' : 's'} sent')
                          : 'Turn on sharing to send pings',
                      style: const TextStyle(
                          color: kText, fontWeight: FontWeight.w600),
                    ),
                    if (lastPing != null) ...[
                      const SizedBox(height: 2),
                      Text('Last: $lastPing',
                          style: const TextStyle(color: kTextDim, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              GlassButton(
                label: 'Send ping',
                icon: Icons.send,
                expand: false,
                busy: pingBusy,
                onPressed: onPing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: kText));
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: kAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kAccent),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: kTextDim)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<NotificationPage> _future;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.notifications();
  }

  Future<void> _refresh() async {
    final f = widget.api.notifications();
    setState(() => _future = f);
    await f.catchError((_) => NotificationPage(items: const [], nextCursor: null, unreadCount: 0));
  }

  Future<void> _markAll() async {
    setState(() => _markingAll = true);
    try {
      await widget.api.markAllNotificationsRead();
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.detail), backgroundColor: kDanger),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _markOne(AppNotification n) async {
    if (n.read) return;
    try {
      await widget.api.markNotificationRead(n.id);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.detail), backgroundColor: kDanger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kAccent,
      backgroundColor: kBg1,
      onRefresh: _refresh,
      child: FutureBuilder<NotificationPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _CenteredLoader(label: 'Loading notifications…');
          }
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                ErrorBanner(
                  message: snap.error is ApiException
                      ? (snap.error as ApiException).detail
                      : '${snap.error}',
                  onRetry: _refresh,
                ),
              ],
            );
          }
          final page = snap.data;
          final items = page?.items ?? const <AppNotification>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Pill(
                        icon: Icons.mark_email_unread_outlined,
                        label: '${page?.unreadCount ?? 0} unread'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: (items.isEmpty || _markingAll) ? null : _markAll,
                      icon: _markingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kAccent))
                          : const Icon(Icons.done_all, size: 18, color: kAccent),
                      label: const Text('Mark all read',
                          style: TextStyle(color: kAccent)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 100),
                          EmptyState(
                            icon: Icons.notifications_off_outlined,
                            title: 'No notifications',
                            subtitle:
                                'Job assignments and delivery updates will show up here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _NotificationTile(
                          n: items[i],
                          onTap: () => _markOne(items[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: n.read ? null : onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: n.read ? 0.08 : 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(n.category, n.type),
                color: n.read ? kTextDim : kAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title.isEmpty ? n.type : n.title,
                        style: TextStyle(
                            color: kText,
                            fontSize: 15,
                            fontWeight:
                                n.read ? FontWeight.w600 : FontWeight.w800),
                      ),
                    ),
                    if (!n.read)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: kAccent, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(n.body,
                      style: const TextStyle(color: kTextDim, height: 1.35)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (n.category.isNotEmpty)
                      Pill(label: n.category),
                    const Spacer(),
                    Text(_fmtTime(n.createdAt),
                        style: const TextStyle(color: kTextDim, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String category, String type) {
    final key = '$category $type'.toLowerCase();
    if (key.contains('order') || key.contains('job') || key.contains('assign')) {
      return Icons.assignment_outlined;
    }
    if (key.contains('deliver')) return Icons.local_shipping_outlined;
    if (key.contains('pay')) return Icons.payments_outlined;
    return Icons.notifications_none;
  }

  String _fmtTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
