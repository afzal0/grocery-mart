package com.grocerymart.api.identity;

import org.springframework.http.HttpStatus;

/** A client-facing error carrying an HTTP status; rendered as RFC 9457 problem+json. */
public class ApiException extends RuntimeException {
    private final HttpStatus status;

    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public static ApiException badRequest(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, message);
    }

    public HttpStatus status() {
        return status;
    }
}
