import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<dynamic> _orders = const [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/orders');
      if (!mounted) return;
      setState(() => _orders = (res as List?) ?? const []);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderDetailScreen(orderId: '${order['orderId']}'),
    ));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Gm.accent,
        backgroundColor: Gm.bg1,
        onRefresh: refresh,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 200),
                GmLoading(label: 'Loading orders…'),
              ])
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 160),
                    GmError(message: _error!, onRetry: refresh),
                  ])
                : _orders.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 200),
                        GmEmpty(
                            message:
                                'No orders yet. Build a basket to get started.',
                            icon: Icons.receipt_long_outlined),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        children: [
                          const GmGradientText('Your orders',
                              style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          ..._orders.map((o) => _OrderCard(
                                order: o as Map<String, dynamic>,
                                onTap: () => _open(o),
                              )),
                        ],
                      ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) =
        GmUi.statusChip(order['status'] as String?);
    final (payLabel, payColor) =
        GmUi.paymentChip(order['paymentStatus'] as String?);
    final currency = '${order['currency'] ?? 'AUD'}';
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  'Order #${_shortId('${order['orderId']}')}',
                  style: const TextStyle(
                      color: Gm.text, fontWeight: FontWeight.w700)),
            ),
            Text(GmUi.money(order['grandTotal'] as num?, currency),
                style: const TextStyle(
                    color: Gm.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            GmBadge(statusLabel, color: statusColor),
            GmBadge(payLabel, color: payColor),
            if (order['createdAt'] != null)
              GmBadge(_fmtDate(order['createdAt']), color: Gm.textDim),
          ]),
        ],
      ),
    );
  }

  String _shortId(String id) =>
      id.length > 8 ? id.substring(0, 8) : id;

  String _fmtDate(dynamic iso) {
    final dt = DateTime.tryParse('$iso');
    if (dt == null) return '$iso';
    final l = dt.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}
