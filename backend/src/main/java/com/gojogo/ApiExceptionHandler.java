package com.gojogo;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.util.Map;

/**
 * Consistent `{"message": ...}` error bodies — the iOS client surfaces this field.
 */
@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, String>> validation(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldErrors().stream()
            .findFirst()
            .map(f -> f.getField() + " " + f.getDefaultMessage())
            .orElse("Invalid request");
        return ResponseEntity.badRequest().body(Map.of("message", message));
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    ResponseEntity<Map<String, String>> malformed(Exception e) {
        return ResponseEntity.badRequest().body(Map.of("message", "Malformed request"));
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<Map<String, String>> conflict(DataIntegrityViolationException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("message", "Conflicting data"));
    }

    /**
     * An empty wallet, from wherever it was noticed — a checkout, a payout, a
     * stake. Handled once here rather than in each vertical because the answer
     * is the same everywhere and the client keys off the status: <b>402</b> is
     * what tells the app to offer a top-up rather than an apology.
     */
    @ExceptionHandler(com.gojogo.payments.InsufficientFundsException.class)
    ResponseEntity<Map<String, String>> insufficientFunds(
            com.gojogo.payments.InsufficientFundsException e) {
        long shortfall = e.shortfallMinor();
        return ResponseEntity.status(HttpStatus.PAYMENT_REQUIRED).body(Map.of(
            "message", "Your wallet is short by %d.%02d — top up to continue"
                .formatted(shortfall / 100, shortfall % 100),
            "shortfallMinor", String.valueOf(shortfall),
            "availableMinor", String.valueOf(e.availableMinor())));
    }
}
