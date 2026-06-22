import 'package:flutter/material.dart';

import '../api.dart';
import '../location.dart';
import '../theme.dart';
import 'cart_screen.dart';

class _BasketItem {
  _BasketItem({required this.canonicalProductId, required this.label, this.quantity = 1});
  final String canonicalProductId;
  final String label;
  int quantity;
}

/// Build a basket of canonical items and compare the whole-basket price across nearby stores,
/// ranked cheapest-fully-available first. Location is automatic (no manual lat/lng).
class BasketScreen extends StatefulWidget {
  const BasketScreen({super.key, required this.onCheckedOut});
  final VoidCallback onCheckedOut;

  @override
  State<BasketScreen> createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final _api = ApiClient.instance;
  final _loc = GmLocation.instance;
  final List<_BasketItem> _items = [];

  bool _comparing = false;
  bool _resolving = false;
  String? _compareError;
  Map<String, dynamic>? _compareResult;

  @override
  void initState() {
    super.initState();
    _loc.ensure().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addItem() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (picked == null) return;
    final id = '${picked['id']}';
    setState(() {
      final existing = _items.where((e) => e.canonicalProductId == id).toList();
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _items.add(_BasketItem(
          canonicalProductId: id,
          label: [picked['brand'], picked['name']].where((e) => e != null && '$e'.isNotEmpty).join(' '),
        ));
      }
      _compareResult = null; // basket changed -> stale results
    });
  }

  Future<void> _compare() async {
    if (_items.isEmpty) {
      GmUi.snack(context, 'Add at least one item first.', error: true);
      return;
    }
    setState(() {
      _comparing = true;
      _compareError = null;
    });
    try {
      var res = await _api.post('/basket/compare', body: {
        'lat': _loc.lat,
        'lng': _loc.lng,
        'radiusKm': 30,
        'items': _items.map((e) => {'canonicalProductId': e.canonicalProductId, 'quantity': e.quantity}).toList(),
      }) as Map<String, dynamic>;
      // Demo data is in Sydney — fall back if the detected location has nothing nearby.
      final stores = (res['stores'] as List?) ?? const [];
      if (stores.isEmpty && (_loc.lat != kSydneyLat || _loc.lng != kSydneyLng)) {
        _loc.lat = kSydneyLat;
        _loc.lng = kSydneyLng;
        _loc.label = 'Sydney NSW';
        res = await _api.post('/basket/compare', body: {
          'lat': kSydneyLat,
          'lng': kSydneyLng,
          'radiusKm': 30,
          'items': _items.map((e) => {'canonicalProductId': e.canonicalProductId, 'quantity': e.quantity}).toList(),
        }) as Map<String, dynamic>;
      }
      if (!mounted) return;
      setState(() => _compareResult = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _compareError = e.detail);
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  Future<void> _orderFrom(Map<String, dynamic> store) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final cart = await _api.post('/cart/resolve', body: {
        'storeId': store['shopId'],
        'currency': 'AUD',
        'items': _items.map((e) => {'canonicalProductId': e.canonicalProductId, 'quantity': e.quantity}).toList(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CartScreen(
          cart: cart,
          storeName: '${store['shopName'] ?? 'Store'}',
          lat: _loc.lat,
          lng: _loc.lng,
          onCheckedOut: widget.onCheckedOut,
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
    final allStores = (_compareResult?['stores'] as List?) ?? const [];
    // Only stores that actually carry the basket. "available" = has every item; "partial" =
    // has at least one (shown only as a fallback when no store has everything). Stores with
    // nothing from the basket are hidden.
    final available = allStores.where((s) => (s as Map)['fullyAvailable'] == true).toList();
    final partial = allStores.where((s) {
      final m = s as Map;
      return m['fullyAvailable'] != true && ((m['itemsAvailable'] as num?) ?? 0) > 0;
    }).toList();
    final shown = available.isNotEmpty ? available : partial;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 110),
        children: [
          Text('Compare your basket', style: Gm.display(26, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Add items, then find the cheapest fully-stocked store near you.',
              style: TextStyle(color: Gm.textDim, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 16, color: Gm.accent),
            const SizedBox(width: 4),
            Text('Comparing near ${_loc.label}',
                style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 16),

          // Your items
          GmGlass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Your items', style: Gm.display(17, weight: FontWeight.w700)),
                const Spacer(),
                GmGhostButton(label: 'Add item', icon: Icons.add_rounded, onPressed: _addItem),
              ]),
              const SizedBox(height: 4),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: GmEmpty(message: 'No items yet. Tap “Add item” to start a basket.', icon: Icons.add_shopping_cart_rounded),
                )
              else
                ..._items.map(_itemRow),
            ]),
          ),
          const SizedBox(height: 14),

          GmButton(
            label: _items.isEmpty ? 'Compare prices' : 'Compare ${_items.length} item${_items.length == 1 ? '' : 's'} across stores',
            icon: Icons.compare_arrows_rounded,
            busy: _comparing,
            onPressed: _comparing || _items.isEmpty ? null : _compare,
          ),
          const SizedBox(height: 18),

          // Results — only stores that have your items
          if (_compareError != null)
            GmError(message: _compareError!, onRetry: _compare)
          else if (_compareResult != null && shown.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: GmEmpty(message: 'No nearby store carries these items.', icon: Icons.storefront_outlined))
          else if (_compareResult != null) ...[
            Text(
              available.isNotEmpty
                  ? '${available.length} store${available.length == 1 ? '' : 's'} ${available.length == 1 ? 'has' : 'have'} your full basket'
                  : 'No store has all ${_items.length} items — closest matches',
              style: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...List.generate(shown.length, (i) => _StoreResultCard(
                  store: shown[i] as Map<String, dynamic>,
                  best: available.isNotEmpty && i == 0, // cheapest fully-available
                  onOrder: _resolving ? null : () => _orderFrom(shown[i] as Map<String, dynamic>),
                )),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(_BasketItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(item.label, style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w600), maxLines: 2)),
        const SizedBox(width: 8),
        _QtyStepper(
          quantity: item.quantity,
          onChanged: (q) => setState(() {
            if (q <= 0) {
              _items.remove(item);
            } else {
              item.quantity = q;
            }
            _compareResult = null;
          }),
        ),
      ]),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.quantity, required this.onChanged});
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1E6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Gm.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity - 1),
          icon: Icon(quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, size: 18, color: Gm.textDim),
        ),
        Text('$quantity', style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w800)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add_rounded, size: 18, color: Gm.accent),
        ),
      ]),
    );
  }
}

class _StoreResultCard extends StatelessWidget {
  const _StoreResultCard({required this.store, required this.onOrder, this.best = false});
  final Map<String, dynamic> store;
  final VoidCallback? onOrder;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final fully = store['fullyAvailable'] == true;
    // basketTotal comes back as a string ("19.99") or null — parse it, never cast.
    final total = num.tryParse('${store['basketTotal'] ?? ''}');
    final avail = store['itemsAvailable'];
    final totalItems = store['itemsTotal'];
    final missing = store['missingCount'];

    return GmGlass(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${store['shopName'] ?? 'Store'}', style: Gm.display(18, weight: FontWeight.w700))),
          const SizedBox(width: 8),
          if (best)
            const GmBadge('Cheapest', color: Gm.fresh, icon: Icons.local_offer_rounded, solid: true)
          else if (fully)
            const GmBadge('In stock', color: Gm.fresh, icon: Icons.check_circle_rounded)
          else
            GmBadge('$missing missing', color: Gm.warn, icon: Icons.error_outline_rounded),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.near_me_rounded, size: 14, color: Gm.textDim),
          const SizedBox(width: 4),
          Text(GmUi.distance(store['distanceM'] as num?), style: const TextStyle(color: Gm.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 14),
          const Icon(Icons.inventory_2_outlined, size: 14, color: Gm.textDim),
          const SizedBox(width: 4),
          Text('$avail / $totalItems items', style: const TextStyle(color: Gm.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
        const Divider(height: 22, color: Gm.line),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fully ? 'Basket total' : 'Partial basket', style: const TextStyle(color: Gm.textDim, fontSize: 12)),
            const SizedBox(height: 2),
            Text(fully ? GmUi.money(total) : '—',
                style: TextStyle(color: fully ? Gm.text : Gm.textDim, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          const Spacer(),
          GmButton(
            label: 'Order',
            expand: false,
            icon: Icons.shopping_cart_rounded,
            onPressed: onOrder,
          ),
        ]),
      ]),
    );
  }
}

/// Bottom-sheet to search the canonical catalog and pick a product.
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _api = ApiClient.instance;
  final _query = TextEditingController();
  bool _busy = false;
  String? _error;
  List<dynamic>? _results;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _api.get('/catalog/canonical/search', query: {'q': q});
      setState(() => _results = (res as List?) ?? const []);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Gm.surface, borderRadius: BorderRadius.circular(Gm.radius)),
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Gm.line, borderRadius: BorderRadius.circular(99))),
            ),
            Text('Add a product', style: Gm.display(19, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      hintText: 'Search atta, dal, rice, paneer…', prefixIcon: Icon(Icons.search_rounded, color: Gm.accent)),
                  style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              GmButton(label: 'Search', expand: false, busy: _busy, onPressed: _busy ? null : _search),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: _busy
                  ? const GmLoading()
                  : _error != null
                      ? GmError(message: _error!, onRetry: _search)
                      : _results == null
                          ? const GmEmpty(message: 'Search the catalog to add items.', icon: Icons.search_rounded)
                          : _results!.isEmpty
                              ? const GmEmpty(message: 'No matches. Try “atta” or “dal”.')
                              : ListView.separated(
                                  itemCount: _results!.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) {
                                    final m = _results![i] as Map<String, dynamic>;
                                    final grad = Gm.imageGradient('${m['name']}');
                                    return GmGlass(
                                      onTap: () => Navigator.of(context).pop(m),
                                      padding: const EdgeInsets.all(10),
                                      child: Row(children: [
                                        Container(
                                          width: 46, height: 46,
                                          decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(12)),
                                          alignment: Alignment.center,
                                          child: const Text('🛒', style: TextStyle(fontSize: 20)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text([m['brand'], m['name']].where((e) => e != null).join(' '),
                                                style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w700)),
                                            if (m['size_label'] != null)
                                              Text('${m['size_label']}', style: const TextStyle(color: Gm.textDim, fontSize: 12.5)),
                                          ]),
                                        ),
                                        const Icon(Icons.add_circle_rounded, color: Gm.accent),
                                      ]),
                                    );
                                  },
                                ),
            ),
          ]),
        ),
      ),
    );
  }
}
