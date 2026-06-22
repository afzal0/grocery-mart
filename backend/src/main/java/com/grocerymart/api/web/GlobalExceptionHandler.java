package com.grocerymart.api.web;

import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.grocerymart.api.identity.ApiException;

/** Renders errors as RFC 9457 application/problem+json (the project's error convention). */
@RestControllerAdvice
public class GlobalExceptionHandler {

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
}
