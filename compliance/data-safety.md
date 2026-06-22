# Google Play Data Safety — Grocery-Mart

This declaration must match the iOS privacy manifest (`PrivacyInfo.xcprivacy`) and the privacy policy.

## Data collected

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|-----------|--------|---------|-----------|
| Name | Yes | No | Account management | Required |
| Email address | Yes | No | Account management, support | Required |
| Phone number | Yes | No | Authentication (OTP) | Required (customers) |
| Approximate/precise location | Yes | No | Delivery routing & live tracking | Required during active delivery (drivers); consented |
| Purchase history | Yes | No | App functionality (orders, settlement) | Required |
| Payment info | Yes (via Stripe) | No | Process payments | Required |
| Device/other IDs (FCM token) | Yes | No | Push notifications | Optional (can opt out) |
| User content (reviews) | Yes | No | App functionality | Optional |

## Security practices

- Data is encrypted in transit (HTTPS/TLS).
- Users can request deletion of their data in-app (Account → Delete Account).
- Users can request a data export in-app (Account → Download my data).
- Driver location sharing is consented and limited to active deliveries.

## Data sharing

No personal data is sold or shared with third parties for advertising. Payment processing is
performed by Stripe under its own privacy terms; we do not store full card numbers.
