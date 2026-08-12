import 'package:flutter/material.dart';

import '../theme.dart';

/// The order money breakdown, shared by the cart and the order detail screen (the two had
/// drifted copies of the same four rows).
///
/// Every charge the customer pays is named before they pay it: items, delivery, and the flat
/// service fee. GST is shown as a component already inside the total, not an addition.
class TotalsCard extends StatelessWidget {
  const TotalsCard({
    super.key,
    required this.totals,
    this.creditsLabel = 'Credits you\'ll earn',
  });

  /// Either a `/carts/{id}/total` response or an order view — both carry the same keys.
  final Map<String, dynamic> totals;

  /// "Credits you'll earn" before payment; "Credits earned" afterwards.
  final String creditsLabel;

  @override
  Widget build(BuildContext context) {
    final currency = '${totals['currency'] ?? 'AUD'}';
    final credits = (totals['creditsEarned'] as num?) ?? 0;
    final platformFee = totals['platformFee'] as num?;

    return GmGlass(
      child: Column(
        children: [
          _row('Items subtotal', totals['itemsSubtotal'] as num?, currency),
          const SizedBox(height: 8),
          _row('Delivery fee', totals['deliveryFee'] as num?, currency),
          if (platformFee != null) ...[
            const SizedBox(height: 8),
            _row('Service & platform fee', platformFee, currency),
          ],
          const SizedBox(height: 8),
          _row('GST (incl.)', totals['gstInclusive'] as num?, currency, dim: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: Gm.lineSoft),
          ),
          _row('Total', totals['grandTotal'] as num?, currency, strong: true),
          if (credits > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Gm.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(Gm.radiusSm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, size: 17, color: Gm.accent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(creditsLabel,
                        style: const TextStyle(
                            fontSize: 13.5, color: Gm.accent, fontWeight: FontWeight.w500)),
                  ),
                  Text('+${credits.toStringAsFixed(2)}',
                      style: Gm.money(14.5, color: Gm.accent, weight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, num? amount, String currency,
      {bool strong = false, bool dim = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: strong ? 15.5 : 14,
            color: dim ? Gm.textFaint : (strong ? Gm.text : Gm.textDim),
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          GmUi.money(amount, currency),
          style: Gm.money(strong ? 17 : 14,
              weight: strong ? FontWeight.w700 : FontWeight.w500,
              color: dim ? Gm.textFaint : Gm.text),
        ),
      ],
    );
  }
}
