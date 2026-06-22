import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.initial});
  final String orderId;
  final Map<String, dynamic>? initial;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _order;
  bool _paying = false;
  bool _refunding = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _order = widget.initial;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/orders/${widget.orderId}');
      if (!mounted) return;
      setState(() {
        _order = res as Map<String, dynamic>;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.detail;
          _loading = false;
        });
      }
    }
  }

  Future<void> _payWallet() async {
    setState(() => _paying = true);
    try {
      await _api.post('/orders/${widget.orderId}/pay/wallet');
      if (!mounted) return;
      GmUi.snack(context, 'Paid from wallet.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _payCard() async {
    setState(() => _paying = true);
    try {
      final res = await _api.post('/orders/${widget.orderId}/pay/card')
          as Map<String, dynamic>;
      if (!mounted) return;
      // Dev build: a real client would confirm the PaymentIntent via Stripe.
      GmUi.snack(context,
          'Card payment initiated (intent ${_short('${res['paymentIntentId']}')}).');
      await _load();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _refund() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Refund order?',
        message: 'This will request a refund for this order.',
        confirmLabel: 'Refund',
      ),
    );
    if (confirm != true) return;
    setState(() => _refunding = true);
    try {
      await _api.post('/orders/${widget.orderId}/refund');
      if (!mounted) return;
      GmUi.snack(context, 'Refund requested.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
  }

  void _track() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderTrackingScreen(orderId: widget.orderId),
    ));
  }

  String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final currency = '${o?['currency'] ?? 'AUD'}';
    final paymentStatus = o?['paymentStatus'] as String?;
    final status = o?['status'] as String?;
    final items = (o?['items'] as List?) ?? const [];

    final pendingPayment = paymentStatus == 'pending_payment';
    final paid = paymentStatus == 'paid';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: Text('Order #${_short(widget.orderId)}',
            style: const TextStyle(color: Gm.text, fontSize: 17)),
        actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: Gm.text)),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading(label: 'Loading order…')
              : _error != null && o == null
                  ? GmError(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          () {
                            final (l, c) = GmUi.statusChip(status);
                            return GmBadge(l, color: c);
                          }(),
                          () {
                            final (l, c) = GmUi.paymentChip(paymentStatus);
                            return GmBadge(l, color: c);
                          }(),
                        ]),
                        const SizedBox(height: 16),

                        // Items
                        GmGlass(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Items',
                                  style: TextStyle(
                                      color: Gm.text,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              if (items.isEmpty)
                                const Text('No item breakdown.',
                                    style: TextStyle(color: Gm.textDim))
                              else
                                ...items.map((it) {
                                  final m = it as Map<String, dynamic>;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                            '${m['qty']} × ${m['name']}',
                                            style: const TextStyle(
                                                color: Gm.text)),
                                      ),
                                      Text(
                                          GmUi.money(
                                              m['unitPrice'] as num?, currency),
                                          style: const TextStyle(
                                              color: Gm.textDim)),
                                    ]),
                                  );
                                }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Totals
                        GmGlass(
                          child: Column(children: [
                            _row('Items subtotal',
                                GmUi.money(o?['itemsSubtotal'] as num?, currency)),
                            const SizedBox(height: 6),
                            _row('Delivery fee',
                                GmUi.money(o?['deliveryFee'] as num?, currency)),
                            const SizedBox(height: 6),
                            _row('GST (incl.)',
                                GmUi.money(o?['gstInclusive'] as num?, currency)),
                            const Divider(
                                color: Color(0x22FFFFFF), height: 22),
                            _row(
                                'Grand total',
                                GmUi.money(
                                    o?['grandTotal'] as num?, currency),
                                bold: true),
                          ]),
                        ),
                        const SizedBox(height: 12),

                        // Delivery info
                        if (o?['deliveryAddress'] != null)
                          GmGlass(
                            child: Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  color: Gm.accent2, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('${o?['deliveryAddress']}',
                                    style:
                                        const TextStyle(color: Gm.text)),
                              ),
                            ]),
                          ),
                        const SizedBox(height: 18),

                        // Actions
                        if (pendingPayment) ...[
                          const Text('Pay for this order',
                              style: TextStyle(
                                  color: Gm.text,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          GmButton(
                            label: 'Pay with wallet',
                            icon: Icons.account_balance_wallet_outlined,
                            busy: _paying,
                            onPressed: _paying ? null : _payWallet,
                          ),
                          const SizedBox(height: 10),
                          GmGhostButton(
                            label: 'Pay with card',
                            icon: Icons.credit_card,
                            color: Gm.accent2,
                            busy: _paying,
                            onPressed: _paying ? null : _payCard,
                          ),
                          const SizedBox(height: 14),
                        ],

                        GmGhostButton(
                          label: 'Track delivery',
                          icon: Icons.local_shipping_outlined,
                          color: Gm.accent,
                          onPressed: _track,
                        ),

                        if (paid) ...[
                          const SizedBox(height: 10),
                          GmGhostButton(
                            label: 'Request refund',
                            icon: Icons.undo,
                            color: Gm.danger,
                            busy: _refunding,
                            onPressed: _refunding ? null : _refund,
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: bold ? Gm.text : Gm.textDim,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        Text(value,
            style: TextStyle(
                color: Gm.text,
                fontSize: bold ? 18 : 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ],
    );
  }
}

/// Polls GET /orders/{id}/tracking every ~4s.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _api = ApiClient.instance;
  Timer? _timer;
  Map<String, dynamic>? _tracking;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final res = await _api.get('/orders/${widget.orderId}/tracking');
      if (!mounted) return;
      setState(() {
        _tracking = res as Map<String, dynamic>;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.detail;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _tracking;
    final state = t?['state'] as String?;
    final phase = t?['phase'] as String?;
    final orderStatus = t?['orderStatus'] as String?;
    final eta = t?['etaMinutes'];
    final loc = t?['location'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Live tracking',
            style: TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading(label: 'Connecting…')
              : _error != null && t == null
                  ? GmError(message: _error!, onRetry: _poll)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      children: [
                        GmGlass(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            const Icon(Icons.local_shipping,
                                color: Gm.accent, size: 48),
                            const SizedBox(height: 14),
                            GmGradientText(
                              GmUi.titleize(
                                  orderStatus ?? state ?? 'pending'),
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800),
                            ),
                            if (eta != null) ...[
                              const SizedBox(height: 8),
                              Text('ETA ~$eta min',
                                  style: const TextStyle(
                                      color: Gm.textDim, fontSize: 16)),
                            ],
                          ]),
                        ),
                        const SizedBox(height: 14),
                        _phaseTimeline(orderStatus ?? state),
                        const SizedBox(height: 14),
                        GmGlass(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _info('Delivery state',
                                  GmUi.titleize(state ?? '—')),
                              if (phase != null)
                                _info('Phase', GmUi.titleize(phase)),
                              if (loc != null)
                                _info('Driver location',
                                    '${(loc['lat'] as num?)?.toStringAsFixed(4)}, ${(loc['lng'] as num?)?.toStringAsFixed(4)}'),
                              _info('Auto-refresh', 'Every 4 seconds'),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Gm.textDim)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Gm.text, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _phaseTimeline(String? status) {
    const steps = [
      ('pending', 'Pending', Icons.hourglass_empty),
      ('processing', 'Processing', Icons.inventory_2_outlined),
      ('on_the_way', 'On the way', Icons.local_shipping_outlined),
      ('delivered', 'Delivered', Icons.check_circle_outline),
    ];
    final currentIndex = steps.indexWhere((s) => s.$1 == status);
    return GmGlass(
      child: Column(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final (_, label, icon) = e.value;
          final reached = currentIndex < 0 ? false : i <= currentIndex;
          final color = reached ? Gm.accent : Gm.textDim;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: reached ? Gm.text : Gm.textDim,
                      fontWeight:
                          reached ? FontWeight.w700 : FontWeight.w400)),
              const Spacer(),
              if (i == currentIndex)
                const Icon(Icons.radio_button_checked,
                    color: Gm.accent, size: 16),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = true,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Gm.bg1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gm.radius)),
      title: Text(title, style: const TextStyle(color: Gm.text)),
      content: Text(message, style: const TextStyle(color: Gm.textDim)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Gm.textDim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel,
              style: TextStyle(
                  color: destructive ? Gm.danger : Gm.accent,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
