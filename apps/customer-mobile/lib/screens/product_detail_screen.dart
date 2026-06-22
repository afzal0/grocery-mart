import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.canonicalId,
    required this.title,
    this.subtitle,
  });

  final String canonicalId;
  final String title;
  final String? subtitle;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;

  List<dynamic> _offers = const [];
  Map<String, dynamic>? _rating;
  List<dynamic> _reviews = const [];
  String? _reviewsCursor;
  bool _loadingMore = false;

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
      final id = widget.canonicalId;
      final results = await Future.wait([
        _api.get('/catalog/canonical/$id/offers'),
        _api.get('/products/$id/rating'),
        _api.get('/products/$id/reviews', query: {'limit': 10}),
      ]);
      final offers = (results[0] as List?) ?? const [];
      final rating = results[1] as Map<String, dynamic>?;
      final reviewsPage = results[2] as Map<String, dynamic>?;
      setState(() {
        _offers = offers;
        _rating = rating;
        _reviews = (reviewsPage?['items'] as List?) ?? const [];
        _reviewsCursor = reviewsPage?['nextCursor'] as String?;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreReviews() async {
    if (_reviewsCursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.get('/products/${widget.canonicalId}/reviews',
          query: {'cursor': _reviewsCursor, 'limit': 10}) as Map<String, dynamic>;
      setState(() {
        _reviews = [..._reviews, ...((page['items'] as List?) ?? const [])];
        _reviewsCursor = page['nextCursor'] as String?;
      });
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _writeReview() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(canonicalId: widget.canonicalId),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title,
            style: const TextStyle(color: Gm.text, fontSize: 17)),
        iconTheme: const IconThemeData(color: Gm.text),
      ),
      extendBodyBehindAppBar: true,
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Gm.accent,
              foregroundColor: const Color(0xFF06281C),
              onPressed: _writeReview,
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Write review'),
            ),
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading(label: 'Loading product…')
              : _error != null
                  ? GmError(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: [
                        Text(widget.title,
                            style: const TextStyle(
                                color: Gm.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(widget.subtitle!,
                              style: const TextStyle(color: Gm.textDim)),
                        ],
                        const SizedBox(height: 14),
                        _ratingSummary(),
                        const SizedBox(height: 18),
                        const Text('Prices across stores (cheapest first)',
                            style: TextStyle(
                                color: Gm.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        if (_offers.isEmpty)
                          const GmEmpty(
                              message: 'No stores currently stock this item.',
                              icon: Icons.inventory_2_outlined)
                        else
                          ..._offers.asMap().entries.map((e) =>
                              _OfferRow(offer: e.value, cheapest: e.key == 0)),
                        const SizedBox(height: 18),
                        Row(children: [
                          const Text('Reviews',
                              style: TextStyle(
                                  color: Gm.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Text('(${_reviews.length})',
                              style: const TextStyle(color: Gm.textDim)),
                        ]),
                        const SizedBox(height: 10),
                        if (_reviews.isEmpty)
                          const GmEmpty(
                              message: 'No reviews yet. Be the first!',
                              icon: Icons.reviews_outlined)
                        else
                          ..._reviews
                              .map((r) => _ReviewCard(review: r as Map<String, dynamic>)),
                        if (_reviewsCursor != null) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: GmGhostButton(
                              label: 'Load more',
                              icon: Icons.expand_more,
                              busy: _loadingMore,
                              onPressed: _loadingMore ? null : _loadMoreReviews,
                            ),
                          ),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _ratingSummary() {
    final r = _rating;
    final count = r?['reviewCount'];
    final avg = r?['avgRating'];
    final msg = r?['message'];
    return GmGlass(
      child: Row(children: [
        const Icon(Icons.star, color: Gm.warn, size: 30),
        const SizedBox(width: 12),
        if ((count == null || count == 0))
          Expanded(
            child: Text(msg?.toString() ?? 'No ratings yet',
                style: const TextStyle(color: Gm.textDim)),
          )
        else
          Expanded(
            child: Row(children: [
              Text(avg == null ? '—' : (avg as num).toStringAsFixed(1),
                  style: const TextStyle(
                      color: Gm.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('· $count reviews',
                  style: const TextStyle(color: Gm.textDim)),
            ]),
          ),
      ]),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer, required this.cheapest});
  final dynamic offer;
  final bool cheapest;

  @override
  Widget build(BuildContext context) {
    // snake_case: shop_id, shop_name, price_amount, currency, stock
    final m = offer as Map<String, dynamic>;
    final price = m['price_amount'];
    final currency = (m['currency'] ?? 'AUD').toString();
    final stock = m['stock'];
    final inStock = stock is num ? stock > 0 : true;
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 8),
      strong: cheapest,
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text('${m['shop_name'] ?? 'Store'}',
                      style: const TextStyle(
                          color: Gm.text, fontWeight: FontWeight.w700)),
                ),
                if (cheapest) ...[
                  const SizedBox(width: 8),
                  const GmBadge('Cheapest',
                      color: Gm.accent, icon: Icons.bolt),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                inStock
                    ? (stock is num ? 'In stock · $stock' : 'In stock')
                    : 'Out of stock',
                style: TextStyle(
                    color: inStock ? Gm.textDim : Gm.danger, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Text(GmUi.money(price as num?, currency),
            style: const TextStyle(
                color: Gm.text, fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Row(
                children: List.generate(
                    5,
                    (i) => Icon(
                          i < rating ? Icons.star : Icons.star_border,
                          color: Gm.warn,
                          size: 16,
                        ))),
            const Spacer(),
            Text('${review['author'] ?? 'Anonymous'}',
                style: const TextStyle(color: Gm.textDim, fontSize: 12.5)),
          ]),
          if (review['body'] != null &&
              '${review['body']}'.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${review['body']}',
                style: const TextStyle(color: Gm.text, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.canonicalId});
  final String canonicalId;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _api = ApiClient.instance;
  final _body = TextEditingController();
  int _rating = 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.post('/products/${widget.canonicalId}/reviews',
          body: {'rating': _rating, 'body': _body.text.trim()});
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
        radius: 22,
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Write a review',
                style: TextStyle(
                    color: Gm.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final value = i + 1;
                return IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _rating = value),
                  icon: Icon(
                    value <= _rating ? Icons.star : Icons.star_border,
                    color: Gm.warn,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText: 'Share your experience (optional)'),
              style: const TextStyle(color: Gm.text),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Gm.danger)),
            ],
            const SizedBox(height: 16),
            GmButton(
                label: 'Submit review',
                busy: _busy,
                onPressed: _busy ? null : _submit),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
