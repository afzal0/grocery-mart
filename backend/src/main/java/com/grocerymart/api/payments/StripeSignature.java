package com.grocerymart.api.payments;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Verifies a Stripe-style webhook signature: header is `t=<ts>,v1=<hex hmac>` and the signed
 * payload is `"<ts>.<rawBody>"` under HMAC-SHA256 with the endpoint secret. Constant-time compare.
 * (Story 5.8 / NFR-SEC-04 — the webhook is the ONLY way payments are finalized.)
 */
public final class StripeSignature {
    private StripeSignature() {}

    public static boolean verify(String payload, String sigHeader, String secret) {
        if (sigHeader == null || sigHeader.isBlank()) return false;
        String t = null, v1 = null;
        for (String part : sigHeader.split(",")) {
            String[] kv = part.trim().split("=", 2);
            if (kv.length != 2) continue;
            if (kv[0].equals("t")) t = kv[1];
            else if (kv[0].equals("v1")) v1 = kv[1];
        }
        if (t == null || v1 == null) return false;
        String expected = hmacSha256Hex(t + "." + payload, secret);
        return constantTimeEquals(expected, v1);
    }

    public static String hmacSha256Hex(String data, String secret) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] raw = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(raw.length * 2);
            for (byte b : raw) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            throw new IllegalStateException("HMAC failure", e);
        }
    }

    private static boolean constantTimeEquals(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }
}
