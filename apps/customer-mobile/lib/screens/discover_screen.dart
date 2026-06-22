import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'product_detail_screen.dart';

const double kSydneyLat = -33.8688;
const double kSydneyLng = 151.2093;

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _api = ApiClient.instance;

  final _lat = TextEditingController(text: '$kSydneyLat');
  final _lng = TextEditingController(text: '$kSydneyLng');
  final _radius = TextEditingController(text: '5');
  final _cuisine = TextEditingController();
  final _search = TextEditingController();

  bool _loadingShops = false;
  String? _shopsError;
  List<dynamic>? _shops;

  bool _searching = false;
  String? _searchError;
  List<dynamic>? _results;

  @override
  void initState() {
    super.initState();
    _findShops();
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    _cuisine.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _findShops() async {
    setState(() {
      _loadingShops = true;
      _shopsError = null;
    });
    try {
      final res = await _api.get('/discovery/shops', query: {
        'lat': _lat.text.trim(),
        'lng': _lng.text.trim(),
        'radiusKm': _radius.text.trim().isEmpty ? '5' : _radius.text.trim(),
        if (_cuisine.text.trim().isNotEmpty) 'cuisine': _cuisine.text.trim(),
      });
      setState(() => _shops = (res as List?) ?? const []);
    } on ApiException catch (e) {
      setState(() => _shopsError = e.detail);
    } finally {
      if (mounted) setState(() => _loadingShops = false);
    }
  }

  Future<void> _searchProducts() async {
    final q = _search.text.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final res = await _api.get('/catalog/canonical/search', query: {'q': q});
      setState(() => _results = (res as List?) ?? const []);
    } on ApiException catch (e) {
      setState(() => _searchError = e.detail);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const GmGradientText('Discover',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Find nearby stores and compare product prices.',
              style: TextStyle(color: Gm.textDim)),
          const SizedBox(height: 16),

          // ---- Store discovery filters ----
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
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _radius,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Radius km'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cuisine,
                      decoration: const InputDecoration(
                          labelText: 'Cuisine (optional)'),
                      style: const TextStyle(color: Gm.text),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                GmButton(
                  label: 'Find stores',
                  icon: Icons.search,
                  busy: _loadingShops,
                  onPressed: _loadingShops ? null : _findShops,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_loadingShops)
            const Padding(
                padding: EdgeInsets.all(24), child: GmLoading())
          else if (_shopsError != null)
            GmError(message: _shopsError!, onRetry: _findShops)
          else if (_shops != null && _shops!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: GmEmpty(
                    message: 'No stores within range. Widen your radius.',
                    icon: Icons.storefront_outlined))
          else if (_shops != null)
            ..._shops!.map((s) => _ShopCard(shop: s as Map<String, dynamic>)),

          const SizedBox(height: 24),
          const Divider(color: Color(0x22FFFFFF)),
          const SizedBox(height: 12),

          // ---- Product search ----
          const Text('Search products',
              style: TextStyle(
                  color: Gm.text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GmGlass(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchProducts(),
                  decoration: const InputDecoration(
                      hintText: 'e.g. Basmati Rice, Toor Dal',
                      prefixIcon: Icon(Icons.search, color: Gm.textDim)),
                  style: const TextStyle(color: Gm.text),
                ),
              ),
              const SizedBox(width: 10),
              GmButton(
                  label: 'Go',
                  expand: false,
                  busy: _searching,
                  onPressed: _searching ? null : _searchProducts),
            ]),
          ),
          const SizedBox(height: 12),

          if (_searching)
            const Padding(padding: EdgeInsets.all(24), child: GmLoading())
          else if (_searchError != null)
            GmError(message: _searchError!, onRetry: _searchProducts)
          else if (_results != null && _results!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: GmEmpty(message: 'No products matched your search.'))
          else if (_results != null)
            ..._results!.map((r) => _CanonicalCard(item: r as Map<String, dynamic>)),
        ],
      ),
    );
  }
}

class _ShopCard extends StatefulWidget {
  const _ShopCard({required this.shop});
  final Map<String, dynamic> shop;

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> {
  final _api = ApiClient.instance;
  bool _loadingRating = false;
  Map<String, dynamic>? _rating;

  Future<void> _loadRating() async {
    final shopId = widget.shop['shopId'];
    if (shopId == null) return;
    setState(() => _loadingRating = true);
    try {
      final res = await _api.get('/stores/$shopId/rating');
      setState(() => _rating = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _loadingRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shop;
    final tags = (s['cuisineTags'] as List?)?.cast<dynamic>() ?? const [];
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: _loadRating,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.storefront, color: Gm.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${s['name'] ?? 'Store'}',
                  style: const TextStyle(
                      color: Gm.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
            GmBadge(GmUi.distance(s['distanceM'] as num?),
                color: Gm.accent2, icon: Icons.near_me),
          ]),
          if (s['address'] != null) ...[
            const SizedBox(height: 6),
            Text('${s['address']}',
                style: const TextStyle(color: Gm.textDim, fontSize: 13)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => GmBadge('$t', color: Gm.textDim))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          if (_loadingRating)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Gm.accent)),
            )
          else if (_rating != null)
            _RatingLine(rating: _rating!)
          else
            const Text('Tap to load store rating',
                style: TextStyle(color: Gm.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.rating});
  final Map<String, dynamic> rating;

  @override
  Widget build(BuildContext context) {
    final avg = rating['avgRating'];
    final count = rating['reviewCount'];
    final msg = rating['message'];
    if ((count == null || count == 0) && msg != null) {
      return Text('$msg',
          style: const TextStyle(color: Gm.textDim, fontSize: 12.5));
    }
    return Row(children: [
      const Icon(Icons.star, color: Gm.warn, size: 16),
      const SizedBox(width: 4),
      Text(
        avg == null ? '—' : (avg as num).toStringAsFixed(1),
        style: const TextStyle(color: Gm.text, fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 6),
      Text('($count reviews)',
          style: const TextStyle(color: Gm.textDim, fontSize: 12.5)),
    ]);
  }
}

class _CanonicalCard extends StatelessWidget {
  const _CanonicalCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    // snake_case keys: id, brand, name, size_label, sim
    final brand = item['brand'];
    final name = item['name'];
    final size = item['size_label'];
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          canonicalId: '${item['id']}',
          title: [brand, name].where((e) => e != null).join(' '),
          subtitle: size?.toString(),
        ),
      )),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([brand, name].where((e) => e != null).join(' '),
                  style: const TextStyle(
                      color: Gm.text, fontWeight: FontWeight.w700)),
              if (size != null) ...[
                const SizedBox(height: 4),
                Text('$size',
                    style:
                        const TextStyle(color: Gm.textDim, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: Gm.textDim),
      ]),
    );
  }
}
