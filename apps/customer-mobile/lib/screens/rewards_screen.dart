import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Loyalty credits: balance and recent activity.
///
/// Shows the NUMBER of credits and nothing about how it was arrived at — the calculation is
/// commercially sensitive and stays server-side. There is no redemption path yet, so the copy
/// promises nothing about what a credit is worth.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => RewardsScreenState();
}

class RewardsScreenState extends State<RewardsScreen> {
  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;
  num _balance = 0;
  List<dynamic> _entries = const [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Public so the shell can refresh this tab after an order is placed.
  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.get('/loyalty') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _balance = (res['balanceCredits'] as num?) ?? 0;
        _entries = (res['entries'] as List?) ?? const [];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GmBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _loading
              ? const Center(child: GmLoading(label: 'Loading rewards…'))
              : _error != null
                  ? Center(child: GmError(message: _error!, onRetry: refresh))
                  : RefreshIndicator(
                      color: Gm.accent,
                      onRefresh: refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
                            child: Text('Rewards', style: Gm.display(26)),
                          ),
                          _balanceCard(),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                            child: Text('Activity', style: Gm.display(15, weight: FontWeight.w600)),
                          ),
                          if (_entries.isEmpty)
                            const GmEmpty(
                              title: 'No credits yet',
                              message: 'Place an order and your credits will appear here.',
                            )
                          else
                            GmGlass(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0; i < _entries.length; i++) ...[
                                    if (i > 0)
                                      const Divider(height: 1, thickness: 1, color: Gm.lineSoft),
                                    _entryRow(_entries[i] as Map<String, dynamic>),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _balanceCard() {
    return GmGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Gm.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(Gm.radiusSm),
                ),
                child: const Icon(Icons.card_giftcard_rounded, color: Gm.accent, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your credits',
                        style: TextStyle(fontSize: 13, color: Gm.textDim)),
                    const SizedBox(height: 2),
                    Text(_balance.toStringAsFixed(2),
                        style: Gm.money(32, weight: FontWeight.w700, color: Gm.text)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Gm.surfaceSunk,
              borderRadius: BorderRadius.circular(Gm.radiusSm),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Gm.textDim),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You earn credits on every order you place. Ways to spend them are coming soon.',
                    style: TextStyle(fontSize: 13, color: Gm.textDim, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(Map<String, dynamic> e) {
    final reversed = '${e['type']}' == 'reverse';
    final credits = (e['credits'] as num?) ?? 0;
    final when = DateTime.tryParse('${e['createdAt']}')?.toLocal();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(
            reversed ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
            size: 19,
            color: reversed ? Gm.textFaint : Gm.fresh,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reversed ? 'Order refunded' : 'Order credits',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                  when == null
                      ? 'Order ${'${e['orderId']}'.substring(0, 8)}'
                      : '${when.day}/${when.month}/${when.year} · ${'${e['orderId']}'.substring(0, 8)}',
                  style: const TextStyle(fontSize: 12, color: Gm.textFaint),
                ),
              ],
            ),
          ),
          Text(
            '${reversed ? '−' : '+'}${credits.toStringAsFixed(2)}',
            style: Gm.money(15, color: reversed ? Gm.textFaint : Gm.fresh),
          ),
        ],
      ),
    );
  }
}
