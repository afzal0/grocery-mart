import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'order_detail_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cart,
    required this.storeName,
    required this.lat,
    required this.lng,
    required this.onCheckedOut,
  });

  final Map<String, dynamic> cart;
  final String storeName;
  final double lat;
  final double lng;
  final VoidCallback onCheckedOut;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _api = ApiClient.instance;
  final _address = TextEditingController(
      text: '123 George St, Sydney NSW 2000');

  late Map<String, dynamic> _cart;
  Map<String, dynamic>? _total;
  bool _busy = false; // line mutation in flight
  bool _loadingTotal = false;
  bool _checkingOut = false;
  String? _error;

  // Delivery timing.
  String _timing = 'immediate';
  List<dynamic> _slots = const [];
  String? _selectedSlotId;
  bool _loadingSlots = false;

  String get _cartId => '${_cart['cartId']}';
  String get _storeId => '${_cart['storeId']}';
  String get _currency => '${_cart['currency'] ?? 'AUD'}';

  @override
  void initState() {
    super.initState();
    _cart = widget.cart;
    _loadTotal();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadTotal() async {
    setState(() => _loadingTotal = true);
    try {
      final res = await _api.get('/carts/$_cartId/total',
          query: {'lat': widget.lat, 'lng': widget.lng});
      setState(() => _total = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _loadingTotal = false);
    }
  }

  Future<void> _patchLine(String lineId, int quantity) async {
    setState(() => _busy = true);
    try {
      final res = await _api.patch('/carts/$_cartId/lines/$lineId',
          body: {'quantity': quantity});
      setState(() => _cart = res as Map<String, dynamic>);
      await _loadTotal();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLine(String lineId) async {
    setState(() => _busy = true);
    try {
      final res = await _api.delete('/carts/$_cartId/lines/$lineId');
      setState(() => _cart = res as Map<String, dynamic>);
      await _loadTotal();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final res = await _api.get('/stores/$_storeId/slots')
          as Map<String, dynamic>;
      setState(() => _slots = (res['slots'] as List?) ?? const []);
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _checkout() async {
    if (_address.text.trim().isEmpty) {
      setState(() => _error = 'Enter a delivery address.');
      return;
    }
    if (_timing == 'scheduled' && _selectedSlotId == null) {
      setState(() => _error = 'Pick a delivery slot.');
      return;
    }
    setState(() {
      _checkingOut = true;
      _error = null;
    });
    try {
      final order = await _api.post(
        '/carts/$_cartId/checkout',
        headers: {'Idempotency-Key': ApiClient.newIdempotencyKey()},
        body: {
          'deliveryAddress': _address.text.trim(),
          'lat': widget.lat,
          'lng': widget.lng,
          'timing': _timing,
          if (_timing == 'scheduled') 'slotId': _selectedSlotId,
        },
      ) as Map<String, dynamic>;
      if (!mounted) return;
      // Replace cart with order detail, then bubble up to Orders tab.
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          orderId: '${order['orderId']}',
          initial: order,
        ),
      ));
      if (mounted) widget.onCheckedOut();
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = (_cart['lines'] as List?) ?? const [];
    final missing = (_cart['missingItems'] as List?) ?? const [];
    final ready = _cart['checkoutReady'] == true;
    final subtotal = _cart['itemsSubtotal'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: Text(widget.storeName,
            style: const TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            children: [
              const GmGradientText('Your cart',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),

              if (lines.isEmpty)
                const GmEmpty(
                    message: 'Your cart is empty.',
                    icon: Icons.remove_shopping_cart_outlined)
              else
                ...lines.map((l) => _LineRow(
                      line: l as Map<String, dynamic>,
                      currency: _currency,
                      disabled: _busy,
                      onQty: (q) {
                        final lineId = '${l['lineId']}';
                        if (q <= 0) {
                          _removeLine(lineId);
                        } else {
                          _patchLine(lineId, q);
                        }
                      },
                      onRemove: () => _removeLine('${l['lineId']}'),
                    )),

              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                GmGlass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.warning_amber_rounded,
                            color: Gm.warn, size: 18),
                        SizedBox(width: 8),
                        Text('Unavailable items',
                            style: TextStyle(
                                color: Gm.warn,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 6),
                      ...missing.map((m) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• ${m is Map ? (m['name'] ?? m) : m}',
                                style: const TextStyle(color: Gm.textDim)),
                          )),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              _totalsCard(subtotal),
              const SizedBox(height: 14),
              _deliveryCard(),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Gm.danger)),
              ],
              const SizedBox(height: 16),
              GmButton(
                label: ready ? 'Checkout' : 'Resolve unavailable items first',
                icon: Icons.lock_outline,
                busy: _checkingOut,
                onPressed:
                    (!ready || _checkingOut || lines.isEmpty) ? null : _checkout,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalsCard(dynamic subtotal) {
    final t = _total;
    return GmGlass(
      child: Column(
        children: [
          _totalRow('Items subtotal',
              GmUi.money((t?['itemsSubtotal'] ?? subtotal) as num?, _currency)),
          if (t != null) ...[
            const SizedBox(height: 6),
            _totalRow('Delivery fee',
                GmUi.money(t['deliveryFee'] as num?, _currency)),
            const SizedBox(height: 6),
            _totalRow('GST (incl.)',
                GmUi.money(t['gstInclusive'] as num?, _currency)),
            const Divider(color: Color(0x22FFFFFF), height: 22),
            _totalRow(
              'Grand total',
              GmUi.money(t['grandTotal'] as num?, _currency),
              bold: true,
            ),
          ] else if (_loadingTotal) ...[
            const SizedBox(height: 10),
            const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Gm.accent)),
          ],
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
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

  Widget _deliveryCard() {
    return GmGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Delivery',
              style: TextStyle(
                  color: Gm.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Delivery address',
                prefixIcon: Icon(Icons.location_on_outlined, color: Gm.textDim)),
            style: const TextStyle(color: Gm.text),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _timingChip('Immediate', 'immediate'),
            const SizedBox(width: 10),
            _timingChip('Scheduled', 'scheduled'),
          ]),
          if (_timing == 'scheduled') ...[
            const SizedBox(height: 12),
            if (_slots.isEmpty && !_loadingSlots)
              GmGhostButton(
                  label: 'Load available slots',
                  icon: Icons.schedule,
                  onPressed: _loadSlots)
            else if (_loadingSlots)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Gm.accent)),
              )
            else
              Column(
                children: _slots.map((s) {
                  final m = s as Map<String, dynamic>;
                  final id = '${m['slotId']}';
                  final selected = id == _selectedSlotId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GmGlass(
                      strong: selected,
                      padding: const EdgeInsets.all(12),
                      onTap: () => setState(() => _selectedSlotId = id),
                      child: Row(children: [
                        Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected ? Gm.accent : Gm.textDim,
                            size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_fmtTime(m['windowStart'])} – ${_fmtTime(m['windowEnd'])}',
                            style: const TextStyle(color: Gm.text),
                          ),
                        ),
                        Text('${m['remaining']} left',
                            style: const TextStyle(
                                color: Gm.textDim, fontSize: 12.5)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _timingChip(String label, String value) {
    final selected = _timing == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _timing = value;
          if (value == 'scheduled' && _slots.isEmpty) _loadSlots();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Gm.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(Gm.radiusSm),
            border: Border.all(
                color: selected ? Gm.accent : Gm.glassBorder),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? Gm.text : Gm.textDim,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  String _fmtTime(dynamic iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse('$iso');
    if (dt == null) return '$iso';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.currency,
    required this.disabled,
    required this.onQty,
    required this.onRemove,
  });

  final Map<String, dynamic> line;
  final String currency;
  final bool disabled;
  final ValueChanged<int> onQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final qty = (line['qty'] as num?)?.toInt() ?? 1;
    final available = line['available'] != false;
    final isSub = line['isSubstitution'] == true;
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text('${line['name'] ?? 'Item'}',
                      style: const TextStyle(
                          color: Gm.text, fontWeight: FontWeight.w600)),
                ),
                if (isSub) ...[
                  const SizedBox(width: 6),
                  const GmBadge('Substitute', color: Gm.accent2),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                '${GmUi.money(line['unitPrice'] as num?, currency)} each · ${GmUi.money(line['lineTotal'] as num?, currency)}',
                style: const TextStyle(color: Gm.textDim, fontSize: 12.5),
              ),
              if (!available)
                const Text('Unavailable',
                    style: TextStyle(color: Gm.danger, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Gm.glassBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: disabled ? null : () => onQty(qty - 1),
                  icon: Icon(qty <= 1 ? Icons.delete_outline : Icons.remove,
                      size: 16, color: Gm.textDim),
                ),
                Text('$qty',
                    style: const TextStyle(
                        color: Gm.text, fontWeight: FontWeight.w700)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: disabled ? null : () => onQty(qty + 1),
                  icon: const Icon(Icons.add, size: 16, color: Gm.accent),
                ),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}
