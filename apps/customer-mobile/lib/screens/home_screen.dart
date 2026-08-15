import 'package:flutter/material.dart';

import '../api.dart';
import '../location.dart';
import '../theme.dart';
import 'cart_screen.dart';

/// The storefront. Finds the stores that deliver to the customer, opens the nearest one's
/// catalog straight away, and lets them switch store from a sheet.
///
/// There is deliberately no browsing layer between opening the app and adding groceries: the
/// customer shops one store at a time, and prices shown are the ones they will be charged.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onCheckedOut});

  final VoidCallback? onCheckedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient.instance;
  final _loc = GmLocation.instance;
  final _searchCtrl = TextEditingController();

  bool _bootstrapping = true;
  bool _loadingProducts = false;
  String? _error;

  List<dynamic> _stores = const [];
  Map<String, dynamic>? _store;
  List<dynamic> _products = const [];

  final Map<String, int> _qty = {}; // canonicalProductId -> qty
  bool _resolving = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    await _loc.ensure();
    await _loadStores();
    if (mounted) setState(() => _bootstrapping = false);
  }

  /// No radiusKm here on purpose — the server's default is the delivery radius, so the client
  /// cannot widen it and surface a store that will not deliver.
  Future<void> _loadStores() async {
    try {
      final res = await _api.get('/discovery/shops', query: {
        'lat': '${_loc.lat}',
        'lng': '${_loc.lng}',
      }) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _stores = res;
        _store = res.isNotEmpty ? res.first as Map<String, dynamic> : null;
      });
      if (_store != null) await _loadProducts();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    }
  }

  /// Coordinates are required: without them the server cannot work out the price for this
  /// customer's area and falls back to the store's own.
  Future<void> _loadProducts() async {
    final id = '${_store!['shopId']}';
    setState(() {
      _loadingProducts = true;
      _error = null;
    });
    try {
      final res = await _api.get('/stores/$id/products', query: {
        'lat': '${_loc.lat}',
        'lng': '${_loc.lng}',
      }) as List<dynamic>;
      if (!mounted) return;
      setState(() => _products = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Future<void> _switchStore(Map<String, dynamic> s) async {
    if ('${s['shopId']}' == '${_store?['shopId']}') return;
    setState(() {
      _store = s;
      _products = const [];
      _qty.clear(); // a cart belongs to one store; carrying quantities over would mislead
    });
    await _loadProducts();
  }

  Future<void> _redetect() async {
    await _loc.ensure(force: true);
    if (!mounted) return;
    setState(() => _bootstrapping = true);
    await _loadStores();
    if (mounted) setState(() => _bootstrapping = false);
  }

  Map<String, dynamic> _byCanonical(String cid) =>
      _products.firstWhere((p) => '${p['canonicalProductId']}' == cid,
          orElse: () => <String, dynamic>{}) as Map<String, dynamic>;

  int get _count => _qty.values.fold(0, (a, b) => a + b);

  double get _subtotal {
    double t = 0;
    _qty.forEach((cid, q) => t += ((_byCanonical(cid)['price'] as num?) ?? 0) * q);
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
    if (_resolving || _qty.isEmpty || _store == null) return;
    setState(() => _resolving = true);
    try {
      final cart = await _api.post('/cart/resolve', body: {
        'storeId': '${_store!['shopId']}',
        'currency': 'AUD',
        'lat': _loc.lat,
        'lng': _loc.lng,
        'items': _qty.entries
            .map((e) => {'canonicalProductId': e.key, 'quantity': e.value})
            .toList(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CartScreen(
          cart: cart,
          storeName: '${_store!['name'] ?? 'Store'}',
          lat: _loc.lat,
          lng: _loc.lng,
          onCheckedOut: () {
            setState(() => _qty.clear());
            widget.onCheckedOut?.call();
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

  void _openSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Gm.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose a store', style: Gm.display(19)),
                  const SizedBox(height: 4),
                  Text('${_stores.length} deliver to ${_loc.label}',
                      style: const TextStyle(color: Gm.textDim, fontSize: 13.5)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _stores.length,
                itemBuilder: (_, i) {
                  final s = _stores[i] as Map<String, dynamic>;
                  final selected = '${s['shopId']}' == '${_store?['shopId']}';
                  final tags = (s['cuisineTags'] as List?)?.cast<String>() ?? const [];
                  return ListTile(
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _switchStore(s);
                    },
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: Gm.imageGradient('${s['name']}')),
                        borderRadius: BorderRadius.circular(Gm.radiusSm),
                      ),
                      alignment: Alignment.center,
                      child: Text(Gm.cuisine(tags.isNotEmpty ? tags.first : null).$3,
                          style: const TextStyle(fontSize: 18)),
                    ),
                    title: Text('${s['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: Text(
                      [
                        GmUi.distance(s['distanceM'] as num?),
                        if (s['rating'] != null) '★ ${(s['rating'] as num).toStringAsFixed(1)}',
                      ].join('  ·  '),
                      style: const TextStyle(color: Gm.textDim, fontSize: 12.5),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded, color: Gm.accent, size: 22)
                        : const Icon(Icons.chevron_right_rounded, color: Gm.textFaint),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---- build ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const GmBackground(child: Center(child: GmLoading(label: 'Finding stores near you…')));
    }
    if (_error != null && _store == null) {
      return GmBackground(child: Center(child: GmError(message: _error!, onRetry: _boot)));
    }
    if (_store == null) {
      return GmBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: GmEmpty(
              title: 'No stores deliver here yet',
              message: 'We could not find a store near ${_loc.label}. '
                  'Try again from a different address.',
              action: GmGhostButton(label: 'Check again', onPressed: _redetect),
            ),
          ),
        ),
      );
    }

    final visible = _query.isEmpty
        ? _products
        : _products
            .where((p) => '${(p as Map)['name']}'.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in visible) {
      final m = p as Map<String, dynamic>;
      groups.putIfAbsent('${m['category'] ?? 'Grocery'}', () => []).add(m);
    }

    return GmBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(),
              Expanded(
                child: _loadingProducts
                    ? const Center(child: GmLoading(label: 'Loading catalogue…'))
                    : RefreshIndicator(
                        color: Gm.accent,
                        onRefresh: _loadProducts,
                        child: visible.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  GmEmpty(
                                    title: _query.isEmpty ? 'Nothing in stock' : 'No matches',
                                    message: _query.isEmpty
                                        ? 'This store has no products listed right now.'
                                        : 'Nothing here matches “$_query”.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 4,
                                  bottom: _count > 0 ? 108 : 24,
                                ),
                                itemCount: groups.length,
                                itemBuilder: (_, i) {
                                  final key = groups.keys.elementAt(i);
                                  return _categorySection(key, groups[key]!);
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _count > 0 ? _cartBar() : null,
      ),
    );
  }

  Widget _header() {
    final s = _store!;
    final tags = (s['cuisineTags'] as List?)?.cast<String>() ?? const [];
    final rating = s['rating'] as num?;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Gm.surface,
        border: Border(bottom: BorderSide(color: Gm.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delivery location — tapping re-detects.
          InkWell(
            onTap: _redetect,
            borderRadius: BorderRadius.circular(Gm.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, size: 15, color: Gm.accent),
                  const SizedBox(width: 5),
                  Text('Delivering to ${_loc.label}',
                      style: const TextStyle(
                          fontSize: 12.5, color: Gm.textDim, fontWeight: FontWeight.w500)),
                  const Icon(Icons.refresh_rounded, size: 14, color: Gm.textFaint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Selected store + switcher
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: Gm.imageGradient('${s['name']}')),
                  borderRadius: BorderRadius.circular(Gm.radiusSm),
                ),
                alignment: Alignment.center,
                child: Text(Gm.cuisine(tags.isNotEmpty ? tags.first : null).$3,
                    style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Gm.display(18)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        GmUi.distance(s['distanceM'] as num?),
                        GmUi.eta(s['distanceM'] as num?),
                        if (rating != null) '★ ${rating.toStringAsFixed(1)}',
                      ].join('  ·  '),
                      style: const TextStyle(fontSize: 12.5, color: Gm.textDim),
                    ),
                  ],
                ),
              ),
              if (_stores.length > 1)
                TextButton(
                  onPressed: _openSwitcher,
                  style: TextButton.styleFrom(
                    foregroundColor: Gm.accent,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('Change',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Filters the loaded catalogue on the device — no request per keystroke.
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search this store',
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Gm.textFaint),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: Gm.textFaint,
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySection(String title, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
          child: Text(GmUi.titleize(title), style: Gm.display(15, weight: FontWeight.w600)),
        ),
        GmGlass(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: Gm.lineSoft),
                _productRow(items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final cid = '${p['canonicalProductId']}';
    final qty = _qty[cid] ?? 0;
    final stock = (p['stock'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: Gm.imageGradient('${p['name']}')),
              borderRadius: BorderRadius.circular(Gm.radiusSm),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.25)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(GmUi.money(p['price'] as num?, '${p['currency'] ?? 'AUD'}'),
                        style: Gm.money(14.5, weight: FontWeight.w600)),
                    if (p['size'] != null && '${p['size']}'.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('${p['size']}',
                          style: const TextStyle(fontSize: 12, color: Gm.textFaint)),
                    ],
                    if (stock > 0 && stock <= 5) ...[
                      const SizedBox(width: 8),
                      Text('Only $stock left',
                          style: const TextStyle(
                              fontSize: 11.5, color: Gm.warn, fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _stepper(cid, qty),
        ],
      ),
    );
  }

  Widget _stepper(String cid, int qty) {
    if (qty == 0) {
      return SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: () => _add(cid),
          style: OutlinedButton.styleFrom(
            foregroundColor: Gm.accent,
            side: const BorderSide(color: Gm.accent, width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gm.radiusSm)),
            minimumSize: const Size(64, 34),
          ),
          child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Gm.accent,
        borderRadius: BorderRadius.circular(Gm.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded, () => _remove(cid), 'Remove one'),
          SizedBox(
            width: 26,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Gm.onPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          _stepBtn(Icons.add_rounded, () => _add(cid), 'Add one'),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, String label) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Gm.radiusSm),
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: Gm.onPrimary),
          ),
        ),
      );

  Widget _cartBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom * 0.5),
      decoration: const BoxDecoration(
        color: Gm.surface,
        border: Border(top: BorderSide(color: Gm.line)),
      ),
      child: SafeArea(
        top: false,
        child: GmButton(
          label: _resolving
              ? 'Opening cart…'
              : 'View cart · $_count ${_count == 1 ? 'item' : 'items'} · ${GmUi.money(_subtotal)}',
          busy: _resolving,
          onPressed: _viewCart,
        ),
      ),
    );
  }
}
