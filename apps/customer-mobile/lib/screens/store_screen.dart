import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'cart_screen.dart';

/// A store's "restaurant page": hero header + its catalog grouped by category, with an
/// add-to-cart stepper and a sticky cart bar that resolves a single-store cart and checks out.
class StoreScreen extends StatefulWidget {
  const StoreScreen({
    super.key,
    required this.store,
    required this.lat,
    required this.lng,
    this.onCheckedOut,
  });

  final Map<String, dynamic> store;
  final double lat;
  final double lng;
  final VoidCallback? onCheckedOut;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;
  List<dynamic> _products = const [];
  final Map<String, int> _qty = {}; // canonicalProductId -> qty
  bool _resolving = false;

  String get _shopId => '${widget.store['shopId']}';
  String get _name => '${widget.store['name'] ?? 'Store'}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/stores/$_shopId/products');
      if (!mounted) return;
      setState(() => _products = res as List<dynamic>);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _byCanonical(String cid) =>
      _products.firstWhere((p) => '${p['canonicalProductId']}' == cid, orElse: () => <String, dynamic>{})
          as Map<String, dynamic>;

  int get _count => _qty.values.fold(0, (a, b) => a + b);

  double get _subtotal {
    double t = 0;
    _qty.forEach((cid, q) {
      final p = _byCanonical(cid);
      t += ((p['price'] as num?) ?? 0) * q;
    });
    return t;
  }

  void _add(String cid) => setState(() => _qty[cid] = (_qty[cid] ?? 0) + 1);
  void _remove(String cid) => setState(() {
        final n = (_qty[cid] ?? 0) - 1;
        if (n <= 0) {
          _qty.remove(cid);
        } else {
          _qty[cid] = n;
        }
      });

  Future<void> _viewCart() async {
    if (_resolving || _qty.isEmpty) return;
    setState(() => _resolving = true);
    try {
      final items = _qty.entries.map((e) => {'canonicalProductId': e.key, 'quantity': e.value}).toList();
      final cart = await _api.post('/cart/resolve', body: {
        'storeId': _shopId,
        'currency': 'AUD',
        'items': items,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CartScreen(
          cart: cart,
          storeName: _name,
          lat: widget.lat,
          lng: widget.lng,
          onCheckedOut: () {
            widget.onCheckedOut?.call();
            // pop back to home after checkout
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ));
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = (widget.store['cuisineTags'] as List?)?.cast<String>() ?? const [];
    final emoji = Gm.cuisine(tags.isNotEmpty ? tags.first : null).$3;
    final grad = Gm.imageGradient(_name);
    final rating = widget.store['rating'] as num?;
    final count = (widget.store['reviewCount'] as num?)?.toInt();
    final distM = widget.store['distanceM'] as num?;

    // Group products by category preserving order
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in _products) {
      final m = p as Map<String, dynamic>;
      groups.putIfAbsent('${m['category'] ?? 'Grocery'}', () => []).add(m);
    }

    return Scaffold(
      backgroundColor: Gm.bg0,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 196,
          backgroundColor: grad.last,
          foregroundColor: Colors.white,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Gm.text),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          title: Text(_name, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight)),
              ),
              Positioned(right: -10, top: -14, child: Opacity(opacity: 0.4, child: Text(emoji, style: const TextStyle(fontSize: 170)))),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x55000000)],
                  ),
                ),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: Gm.display(26, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(children: [
                GmRatingPill(rating, count: count),
                _dot(),
                const Icon(Icons.schedule_rounded, size: 15, color: Gm.textDim),
                const SizedBox(width: 4),
                Text(GmUi.eta(distM), style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w700, fontSize: 13)),
                _dot(),
                const Icon(Icons.near_me_rounded, size: 14, color: Gm.textDim),
                const SizedBox(width: 4),
                Text(GmUi.distance(distM), style: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Text(tags.map(Gm.cuisineLabel).join(' · '),
                  style: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w600)),
              if ('${widget.store['address'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${widget.store['address']}', style: const TextStyle(color: Gm.textDim, fontSize: 13)),
              ],
              const Divider(height: 30, color: Gm.line),
            ]),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(hasScrollBody: false, child: Padding(padding: EdgeInsets.only(top: 40), child: GmLoading(label: 'Loading menu…')))
        else if (_error != null)
          SliverFillRemaining(hasScrollBody: false, child: GmError(message: _error!, onRetry: _load))
        else if (_products.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: GmEmpty(message: 'This store has no products listed yet.', icon: Icons.shopping_basket_outlined))
        else
          SliverList(
            delegate: SliverChildListDelegate([
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Text(entry.key, style: Gm.display(18, weight: FontWeight.w700)),
                ),
                ...entry.value.map(_productRow),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 120),
            ]),
          ),
      ]),
      bottomNavigationBar: _count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GmButton(
                  label: _resolving ? 'Preparing cart…' : 'View cart  •  $_count item${_count == 1 ? '' : 's'}  •  ${GmUi.money(_subtotal)}',
                  busy: _resolving,
                  icon: Icons.shopping_cart_rounded,
                  onPressed: _viewCart,
                ),
              ),
            ),
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final cid = '${p['canonicalProductId']}';
    final name = '${p['name'] ?? ''}';
    final brand = '${p['brand'] ?? ''}';
    final size = '${p['size'] ?? ''}';
    final price = p['price'] as num?;
    final rating = p['rating'] as num?;
    final grad = Gm.imageGradient(name + brand);
    final qty = _qty[cid] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.center,
          child: const Text('🛒', style: TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: Gm.text, fontSize: 15.5)),
            const SizedBox(height: 2),
            Text([brand, size].where((s) => s.isNotEmpty).join(' · '), style: const TextStyle(color: Gm.textDim, fontSize: 13)),
            const SizedBox(height: 6),
            Row(children: [
              Text(GmUi.money(price), style: const TextStyle(fontWeight: FontWeight.w800, color: Gm.text, fontSize: 15)),
              if (rating != null) ...[
                const SizedBox(width: 10),
                const Icon(Icons.star_rounded, size: 14, color: Gm.star),
                const SizedBox(width: 2),
                Text(rating.toStringAsFixed(1), style: const TextStyle(color: Gm.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        _stepper(cid, qty),
      ]),
    );
  }

  Widget _stepper(String cid, int qty) {
    if (qty == 0) {
      return SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () => _add(cid),
          style: OutlinedButton.styleFrom(
            foregroundColor: Gm.accent,
            side: const BorderSide(color: Gm.accent, width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Gm.accent, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _stepBtn(Icons.remove_rounded, () => _remove(cid)),
        SizedBox(width: 24, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        _stepBtn(Icons.add_rounded, () => _add(cid)),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkResponse(
        onTap: onTap,
        radius: 22,
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 18, color: Colors.white)),
      );

  Widget _dot() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text('•', style: TextStyle(color: Gm.textDim, fontWeight: FontWeight.w900)));
}
