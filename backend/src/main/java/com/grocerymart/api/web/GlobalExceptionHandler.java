package com.grocerymart.api.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.grocerymart.api.identity.ApiException;

/** Renders errors as RFC 9457 application/problem+json (the project's error convention). */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ProblemDetail handleApi(ApiException ex) {
        return ProblemDetail.forStatusAndDetail(ex.status(), ex.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        ProblemDetail pd = ProblemDetail.forStatus(org.springframework.http.HttpStatus.BAD_REQUEST);
        pd.setTitle("Validation failed");
        var first = ex.getBindingResult().getFieldError();
        pd.setDetail(first != null ? first.getField() + ": " + first.getDefaultMessage() : "invalid request");
        return pd;
    }

    /** Malformed JSON / type mismatch / missing params stay client errors (not 500). */
    @ExceptionHandler({
        org.springframework.http.converter.HttpMessageNotReadableException.class,
        org.springframework.web.bind.MissingServletRequestParameterException.class,
        org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class,
        jakarta.validation.ConstraintViolationException.class,
        IllegalArgumentException.class })
    public ProblemDetail handleBadRequest(Exception ex) {
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        pd.setTitle("Bad Request");
        pd.setDetail("the request could not be processed as submitted");
        return pd;
    }

    /** Preserve Spring Security denials as 403 (the catch-all below must not turn them into 500). */
    @ExceptionHandler(org.springframework.security.access.AccessDeniedException.class)
    public ProblemDetail handleDenied(org.springframework.security.access.AccessDeniedException ex) {
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.FORBIDDEN);
        pd.setTitle("Forbidden");
        pd.setDetail("access denied");
        return pd;
    }

    /** Story 9.13: any unexpected exception → generic problem+json; full detail logged server-side only. */
    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpected(Exception ex) {
        log.error("unhandled exception", ex);   // detail stays in server logs, never in the response
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.INTERNAL_SERVER_ERROR);
        pd.setTitle("Internal Server Error");
        pd.setDetail("an unexpected error occurred");   // no stack trace, SQL, or internal identifiers
        return pd;
    }
}
