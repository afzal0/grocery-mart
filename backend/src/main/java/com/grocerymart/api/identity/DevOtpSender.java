package com.grocerymart.api.identity;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Development OTP sender — logs the code instead of sending an SMS. NEVER a real prod transport;
 * wire Twilio for production. The code is only logged when {@code grocerymart.dev.log-secrets=true}
 * (defaults false) so deployed environments never leak OTP codes to the log stream.
 */
@Component
public class DevOtpSender implements OtpSender {

    private static final Logger log = LoggerFactory.getLogger(DevOtpSender.class);

    private final boolean logSecrets;

    public DevOtpSender(@Value("${grocerymart.dev.log-secrets:false}") boolean logSecrets) {
        this.logSecrets = logSecrets;
    }

    @Override
    public void send(String phone, String code) {
        if (logSecrets) {
            log.warn("DEV OTP for {} is {}  (dev-only; wire Twilio for production)", phone, code);
        } else {
            log.info("OTP dispatched for {} (code suppressed; set grocerymart.dev.log-secrets=true in dev)", phone);
        }
    }
}
