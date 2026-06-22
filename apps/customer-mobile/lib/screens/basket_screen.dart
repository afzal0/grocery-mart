import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'cart_screen.dart';
import 'discover_screen.dart';

class _BasketItem {
  _BasketItem({
    required this.canonicalProductId,
    required this.label,
    this.quantity = 1,
  });
  final String canonicalProductId;
  final String label;
  int quantity;
}

class BasketScreen extends StatefulWidget {
  const BasketScreen({super.key, required this.onCheckedOut});
  final VoidCallback onCheckedOut;

  @override
  State<BasketScreen> createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final _api = ApiClient.instance;
  final _lat = TextEditingController(text: '$kSydneyLat');
  final _lng = TextEditingController(text: '$kSydneyLng');
  final _radius = TextEditingController(text: '5');

  final List<_BasketItem> _items = [];

  bool _comparing = false;
  bool _resolving = false;
  String? _compareError;
  Map<String, dynamic>? _compareResult;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
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
    _BasketItem? existing;
    for (final e in _items) {
      if (e.canonicalProductId == id) {
        existing = e;
        break;
      }
    }
    setState(() {
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _items.add(_BasketItem(
          canonicalProductId: id,
          label: [picked['brand'], picked['name']]
              .where((e) => e != null)
              .join(' '),
        ));
      }
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
      final res = await _api.post('/basket/compare', body: {
        'lat': double.tryParse(_lat.text.trim()) ?? kSydneyLat,
        'lng': double.tryParse(_lng.text.trim()) ?? kSydneyLng,
        'radiusKm': double.tryParse(_radius.text.trim()) ?? 5,
        'items': _items
            .map((e) => {
                  'canonicalProductId': e.canonicalProductId,
                  'quantity': e.quantity,
                })
            .toList(),
      });
      setState(() => _compareResult = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _compareError = e.detail);
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  Future<void> _orderFrom(Map<String, dynamic> store) async {
    if (_resolving) return;
    final storeId = store['shopId'];
    setState(() => _resolving = true);
    try {
      final cart = await _api.post('/cart/resolve', body: {
        'storeId': storeId,
        'currency': 'AUD',
        'items': _items
            .map((e) => {
                  'canonicalProductId': e.canonicalProductId,
                  'quantity': e.quantity,
                })
            .toList(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CartScreen(
          cart: cart,
          storeName: '${store['shopName'] ?? 'Store'}',
          lat: double.tryParse(_lat.text.trim()) ?? kSydneyLat,
          lng: double.tryParse(_lng.text.trim()) ?? kSydneyLng,
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
    final stores = (_compareResult?['stores'] as List?) ?? const [];
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const GmGradientText('Basket compare',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Add items and find the cheapest fully-stocked store.',
              style: TextStyle(color: Gm.textDim)),
          const SizedBox(height: 16),

          GmGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Your items',
                      style: TextStyle(
                          color: Gm.text, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GmGhostButton(
                      label: 'Add item',
                      icon: Icons.add,
                      color: Gm.accent,
                      onPressed: _addItem),
                ]),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: GmEmpty(
                        message: 'No items yet. Tap “Add item”.',
                        icon: Icons.add_shopping_cart),
                  )
                else
                  ..._items.map(_itemRow),
              ],
            ),
          ),
          const SizedBox(height: 12),

          GmGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Longitude'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _radius,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Radius'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                GmButton(
                  label: 'Compare stores',
                  icon: Icons.compare_arrows,
                  busy: _comparing,
                  onPressed: _comparing || _items.isEmpty ? null : _compare,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_comparing)
            const Padding(padding: EdgeInsets.all(24), child: GmLoading())
          else if (_compareError != null)
            GmError(message: _compareError!, onRetry: _compare)
          else if (_compareResult != null && stores.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: GmEmpty(
                    message: 'No stores in range carry these items.',
                    icon: Icons.storefront_outlined))
          else if (_compareResult != null)
            ...stores.map((s) => _StoreResultCard(
                  store: s as Map<String, dynamic>,
                  onOrder: _resolving ? null : () => _orderFrom(s),
                )),
        ],
      ),
    );
  }

  Widget _itemRow(_BasketItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(item.label,
              style: const TextStyle(color: Gm.text), maxLines: 2),
        ),
        _QtyStepper(
          quantity: item.quantity,
          onChanged: (q) => setState(() {
            if (q <= 0) {
              _items.remove(item);
            } else {
              item.quantity = q;
            }
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Gm.glassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity - 1),
          icon: Icon(quantity <= 1 ? Icons.delete_outline : Icons.remove,
              size: 18, color: Gm.textDim),
        ),
        Text('$quantity',
            style: const TextStyle(
                color: Gm.text, fontWeight: FontWeight.w700)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add, size: 18, color: Gm.accent),
        ),
      ]),
    );
  }
}

class _StoreResultCard extends StatelessWidget {
  const _StoreResultCard({required this.store, required this.onOrder});
  final Map<String, dynamic> store;
  final VoidCallback? onOrder;

  @override
  Widget build(BuildContext context) {
    final fully = store['fullyAvailable'] == true;
    final total = store['basketTotal'];
    final avail = store['itemsAvailable'];
    final totalItems = store['itemsTotal'];
    final missing = store['missingCount'];
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 10),
      strong: fully,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${store['shopName'] ?? 'Store'}',
                  style: const TextStyle(
                      color: Gm.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            if (fully)
              const GmBadge('Fully available',
                  color: Gm.accent, icon: Icons.check_circle)
            else
              GmBadge('$missing missing',
                  color: Gm.warn, icon: Icons.error_outline),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.near_me, size: 14, color: Gm.textDim),
            const SizedBox(width: 4),
            Text(GmUi.distance(store['distanceM'] as num?),
                style: const TextStyle(color: Gm.textDim, fontSize: 12.5)),
            const SizedBox(width: 14),
            const Icon(Icons.inventory_2_outlined,
                size: 14, color: Gm.textDim),
            const SizedBox(width: 4),
            Text('$avail / $totalItems items',
                style: const TextStyle(color: Gm.textDim, fontSize: 12.5)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Text(
              fully ? GmUi.money(total as num?) : 'Partial basket',
              style: TextStyle(
                  color: fully ? Gm.text : Gm.textDim,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            GmButton(
              label: 'Order from this store',
              expand: false,
              icon: Icons.shopping_cart_checkout,
              onPressed: onOrder,
            ),
          ]),
        ],
      ),
    );
  }
}

/// Bottom-sheet to search canonical catalog and pick a product.
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
      child: GmGlass(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a product',
                  style: TextStyle(
                      color: Gm.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                        hintText: 'Search catalog…',
                        prefixIcon: Icon(Icons.search, color: Gm.textDim)),
                    style: const TextStyle(color: Gm.text),
                  ),
                ),
                const SizedBox(width: 10),
                GmButton(
                    label: 'Search',
                    expand: false,
                    busy: _busy,
                    onPressed: _busy ? null : _search),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: _busy
                    ? const GmLoading()
                    : _error != null
                        ? GmError(message: _error!, onRetry: _search)
                        : _results == null
                            ? const GmEmpty(
                                message: 'Search the catalog to add items.',
                                icon: Icons.search)
                            : _results!.isEmpty
                                ? const GmEmpty(message: 'No matches.')
                                : ListView.separated(
                                    itemCount: _results!.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, i) {
                                      final m = _results![i]
                                          as Map<String, dynamic>;
                                      return GmGlass(
                                        onTap: () =>
                                            Navigator.of(context).pop(m),
                                        padding: const EdgeInsets.all(12),
                                        child: Row(children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  [m['brand'], m['name']]
                                                      .where((e) => e != null)
                                                      .join(' '),
                                                  style: const TextStyle(
                                                      color: Gm.text,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                if (m['size_label'] != null)
                                                  Text('${m['size_label']}',
                                                      style: const TextStyle(
                                                          color: Gm.textDim,
                                                          fontSize: 12.5)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.add_circle_outline,
                                              color: Gm.accent),
                                        ]),
                                      );
                                    },
                                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
