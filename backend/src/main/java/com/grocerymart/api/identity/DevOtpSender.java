package com.grocerymart.api.identity;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/** Development OTP sender — logs the code instead of sending an SMS. NEVER for prod. */
@Component
public class DevOtpSender implements OtpSender {

    private static final Logger log = LoggerFactory.getLogger(DevOtpSender.class);

    @Override
    public void send(String phone, String code) {
        log.warn("DEV OTP for {} is {}  (dev-only; wire Twilio for production)", phone, code);
    }
}
