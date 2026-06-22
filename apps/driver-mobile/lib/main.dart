import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

// API base: localhost for iOS sim / desktop; pass --dart-define=API_BASE=http://10.0.2.2:8080 for Android emu.
const String apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

void main() => runApp(const GroceryMartDriverApp());

class GroceryMartDriverApp extends StatelessWidget {
  const GroceryMartDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Grocery-Mart Driver',
      debugShowCheckedModeBanner: false,
      home: LandingScreen(
        role: 'Driver',
        tagline: 'Accept assigned jobs, navigate to the store and customer, and update delivery status.',
        accent: Color(0xFFFBBF24),
        accent2: Color(0xFFF97316),
      ),
    );
  }
}

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.role, required this.tagline, required this.accent, required this.accent2});
  final String role;
  final String tagline;
  final Color accent;
  final Color accent2;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String _status = 'pending';
  String _service = '';

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$apiBase/api/v1/ping'));
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (mounted) setState(() { _status = 'online'; _service = (json['service'] as String?) ?? ''; });
      } else if (mounted) {
        setState(() => _status = 'offline');
      }
      client.close();
    } catch (_) {
      if (mounted) setState(() => _status = 'offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _status == 'online'
        ? widget.accent
        : _status == 'offline'
            ? const Color(0xFFF87171)
            : const Color(0xFFFBBF24);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF0B0A07), widget.accent.withValues(alpha: 0.18), const Color(0xFF1B1505)],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 340,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusPill(color: statusColor, label: 'backend $_status${_service.isNotEmpty ? ' · $_service' : ''}'),
                    const SizedBox(height: 20),
                    ShaderMask(
                      shaderCallback: (b) => LinearGradient(colors: [widget.accent, widget.accent2]).createShader(b),
                      child: Text(
                        'Grocery-Mart\n${widget.role}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15, letterSpacing: -0.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(widget.tagline, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFCBB890), height: 1.5, fontSize: 14)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: const Color(0xFF2A1E03),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Go online', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 18),
                    const Text('Liquid Glass · Flutter · Epic 1 walking skeleton',
                        style: TextStyle(color: Color(0xFFCBB890), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 10)])),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Color(0xFFCBB890), fontSize: 12.5)),
        ],
      ),
    );
  }
}
