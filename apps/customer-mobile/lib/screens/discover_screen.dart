import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api.dart';
import '../location.dart';
import '../theme.dart';
import 'product_detail_screen.dart';
import 'store_screen.dart';

/// Home — discover nearby ethnic-grocery stores. Auto-locates the customer, then shows
/// a search bar, promo banners, cuisine categories and image-rich store cards.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.onCheckedOut});
  final VoidCallback? onCheckedOut;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _api = ApiClient.instance;
  final _loc = GmLocation.instance;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<dynamic> _stores = const [];
  String? _cuisine; // null = All

  // Search
  String _query = '';
  bool _searching = false;
  List<dynamic> _results = const [];
  Timer? _debounce;

  static const _cuisines = ['indian', 'pakistani', 'bengali', 'srilankan', 'afghan', 'nepali'];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loc.ensure();
    if (mounted) setState(() {});
    await _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var stores = await _api.get('/discovery/shops', query: {
        'lat': _loc.lat,
        'lng': _loc.lng,
        'radiusKm': 30,
        if (_cuisine != null) 'cuisine': _cuisine,
      }) as List<dynamic>;
      // The demo catalogue lives in Sydney — if the detected location has no stores nearby,
      // fall back to Sydney so there's always something to explore.
      if (stores.isEmpty && _cuisine == null && (_loc.lat != kSydneyLat || _loc.lng != kSydneyLng)) {
        _loc.lat = kSydneyLat;
        _loc.lng = kSydneyLng;
        _loc.label = 'Sydney NSW';
        stores = await _api.get('/discovery/shops', query: {
          'lat': kSydneyLat,
          'lng': kSydneyLng,
          'radiusKm': 30,
        }) as List<dynamic>;
      }
      if (!mounted) return;
      setState(() => _stores = stores);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    try {
      final res = await _api.get('/catalog/canonical/search', query: {'q': q});
      if (!mounted) return;
      setState(() => _results = res as List<dynamic>);
    } on ApiException catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _redetect() async {
    GmUi.snack(context, 'Detecting your location…');
    await _loc.ensure(force: true);
    if (mounted) setState(() {});
    await _loadStores();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        _header(),
        Expanded(
          child: RefreshIndicator(
            color: Gm.accent,
            onRefresh: _loadStores,
            child: _query.isNotEmpty ? _searchBody() : _discoverBody(),
          ),
        ),
      ]),
    );
  }

  // ---- Header: location + search --------------------------------------------------------
  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 14, 14),
      decoration: const BoxDecoration(
        color: Gm.bg0,
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.location_on_rounded, color: Gm.accent, size: 22),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: _redetect,
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DELIVER TO',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Gm.textDim)),
                Row(children: [
                  Flexible(
                    child: Text(_loc.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Gm.text)),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 20, color: Gm.text),
                ]),
              ]),
            ),
          ),
          _circleIcon(Icons.notifications_none_rounded, () {}),
        ]),
        const SizedBox(height: 12),
        _searchBar(),
      ]),
    );
  }

  Widget _searchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Gm.line),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Gm.text),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: Gm.accent),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: Gm.textDim),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
          hintText: 'Search stores, atta, dal, paneer…',
          hintStyle: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: const Color(0xFFFAF1E6), shape: BoxShape.circle, border: Border.all(color: Gm.line)),
        child: Icon(icon, size: 22, color: Gm.text),
      ),
    );
  }

  // ---- Discover body --------------------------------------------------------------------
  Widget _discoverBody() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        const SizedBox(height: 14),
        const _PromoCarousel(),
        const SizedBox(height: 22),
        _sectionTitle('Shop by cuisine'),
        const SizedBox(height: 10),
        _categoryBar(),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(child: _sectionHead(_cuisine == null ? 'Stores near you' : '${Gm.cuisineLabel(_cuisine!)} stores')),
            if (!_loading) Text('${_stores.length} open', style: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 60), child: GmLoading(label: 'Finding stores near you…'))
        else if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 30), child: GmError(message: _error!, onRetry: _loadStores))
        else if (_stores.isEmpty)
          const Padding(
              padding: EdgeInsets.only(top: 50),
              child: GmEmpty(message: 'No stores in range for this filter.', icon: Icons.storefront_outlined))
        else
          ..._stores.map((s) => _StoreCard(
                store: s as Map<String, dynamic>,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StoreScreen(
                    store: s,
                    lat: _loc.lat,
                    lng: _loc.lng,
                    onCheckedOut: widget.onCheckedOut,
                  ),
                )),
              )),
      ],
    );
  }

  Widget _categoryBar() {
    final items = <(String?, String, String)>[
      (null, '🛒', 'All'),
      for (final c in _cuisines) (c, Gm.cuisine(c).$3, Gm.cuisineLabel(c)),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final (key, emoji, label) = items[i];
          final selected = _cuisine == key;
          final (tint, fg, _) = key == null ? (const Color(0xFFFFE9D6), Gm.accent, '') : Gm.cuisine(key);
          return GestureDetector(
            onTap: () {
              setState(() => _cuisine = key);
              _loadStores();
            },
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: selected ? Gm.accent : tint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? Gm.accent : Gm.line, width: selected ? 2 : 1),
                  boxShadow: selected
                      ? [BoxShadow(color: Gm.accent.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 6))]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? Gm.accent : Gm.text)),
            ]),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _sectionHead(t));

  Widget _sectionHead(String t) => Text(t, style: Gm.display(21, weight: FontWeight.w700));

  // ---- Search body ----------------------------------------------------------------------
  Widget _searchBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
      children: [
        Text('Results for "$_query"', style: const TextStyle(color: Gm.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (_searching)
          const Padding(padding: EdgeInsets.only(top: 40), child: GmLoading())
        else if (_results.isEmpty)
          const Padding(
              padding: EdgeInsets.only(top: 50),
              child: GmEmpty(message: 'No products match. Try “atta”, “dal”, “rice”.', icon: Icons.search_off_rounded))
        else
          ..._results.map((r) {
            final p = r as Map<String, dynamic>;
            final name = '${p['name'] ?? ''}';
            final brand = '${p['brand'] ?? ''}';
            final size = '${p['size_label'] ?? ''}';
            final grad = Gm.imageGradient(name);
            return GmGlass(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProductDetailScreen(
                  canonicalId: '${p['id']}',
                  title: name,
                  subtitle: [brand, size].where((s) => s.isNotEmpty).join(' · '),
                ),
              )),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('🛒', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: Gm.text, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text([brand, size].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(color: Gm.textDim, fontSize: 13)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Gm.textDim),
              ]),
            );
          }),
      ],
    );
  }
}

// ===========================================================================================
// Store card (Uber-Eats style)
// ===========================================================================================
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onTap});
  final Map<String, dynamic> store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${store['name'] ?? 'Store'}';
    final tags = (store['cuisineTags'] as List?)?.cast<String>() ?? const [];
    final primaryCuisine = tags.isNotEmpty ? tags.first : null;
    final emoji = Gm.cuisine(primaryCuisine).$3;
    final grad = Gm.imageGradient(name);
    final distM = store['distanceM'] as num?;
    final rating = store['rating'] as num?;
    final count = (store['reviewCount'] as num?)?.toInt();
    final freeDelivery = (distM ?? 9999) < 3000;
    final fee = freeDelivery ? null : (2.49 + ((distM ?? 0) / 1000) * 0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: GmGlass(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // "Photo" header
          Stack(children: [
            Container(
              height: 118,
              width: double.infinity,
              decoration: BoxDecoration(gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Stack(children: [
                Positioned(right: -8, bottom: -16, child: Opacity(opacity: 0.32, child: Text(emoji, style: const TextStyle(fontSize: 120)))),
                Align(alignment: Alignment.center, child: Text(emoji, style: const TextStyle(fontSize: 46))),
              ]),
            ),
            Positioned(
              left: 12, top: 12,
              child: GmBadge(freeDelivery ? 'Free delivery' : 'Open now',
                  color: freeDelivery ? Gm.fresh : Gm.accent, solid: true, icon: freeDelivery ? Icons.delivery_dining_rounded : Icons.schedule_rounded),
            ),
            Positioned(
              right: 12, top: 10,
              child: Container(
                width: 34, height: 34,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.favorite_border_rounded, size: 18, color: Gm.accent),
              ),
            ),
          ]),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gm.display(18, weight: FontWeight.w700))),
                const SizedBox(width: 8),
                GmRatingPill(rating, count: count),
              ]),
              const SizedBox(height: 5),
              Text(tags.map(Gm.cuisineLabel).join(' · '), style: const TextStyle(color: Gm.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 15, color: Gm.textDim),
                const SizedBox(width: 4),
                Text(GmUi.eta(distM), style: const TextStyle(color: Gm.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                _dot(),
                Icon(Icons.delivery_dining_rounded, size: 16, color: freeDelivery ? Gm.fresh : Gm.textDim),
                const SizedBox(width: 4),
                Text(freeDelivery ? 'Free' : GmUi.money(fee),
                    style: TextStyle(color: freeDelivery ? Gm.fresh : Gm.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                _dot(),
                const Icon(Icons.near_me_rounded, size: 14, color: Gm.textDim),
                const SizedBox(width: 4),
                Text(GmUi.distance(distM), style: const TextStyle(color: Gm.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dot() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text('•', style: TextStyle(color: Gm.textDim, fontWeight: FontWeight.w900)));
}

// ===========================================================================================
// Promo banner carousel
// ===========================================================================================
class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();
  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _ctrl = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _page = 0;

  static const _promos = [
    ('Free delivery', 'On your first 3 orders over \$30', '🛵', [Color(0xFFFF8A3D), Color(0xFFF4511E)]),
    ('Compare & save', 'Same atta, dal & spices — cheapest store wins', '🌶️', [Color(0xFF34D399), Color(0xFF0FA968)]),
    ('Festive specials', 'Sweets, ghee & dry fruits, fresh in store', '🪔', [Color(0xFFA78BFA), Color(0xFF7C3AED)]),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final next = (_page + 1) % _promos.length;
      _ctrl.animateToPage(next, duration: const Duration(milliseconds: 480), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _ctrl,
          onPageChanged: (i) => setState(() => _page = i),
          itemCount: _promos.length,
          itemBuilder: (_, i) {
            final (title, sub, emoji, grad) = _promos[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: grad.last.withValues(alpha: 0.34), blurRadius: 18, offset: const Offset(0, 10))],
                ),
                child: Stack(children: [
                  Positioned(right: -10, bottom: -22, child: Opacity(opacity: 0.85, child: Text(emoji, style: const TextStyle(fontSize: 130)))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(title, style: Gm.display(25, weight: FontWeight.w800, color: Colors.white, height: 1.05)),
                      const SizedBox(height: 6),
                      SizedBox(width: 200, child: Text(sub, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3))),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        child: Text('Order now', style: TextStyle(color: grad.last, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_promos.length, (i) {
        final on = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(color: on ? Gm.accent : Gm.line, borderRadius: BorderRadius.circular(999)),
        );
      })),
    ]);
  }
}
