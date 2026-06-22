package com.grocerymart.api.identity;

/** Delivers a one-time code to a phone. Dev impl logs it; prod swaps in Twilio (R17). */
public interface OtpSender {
    void send(String phone, String code);
}
