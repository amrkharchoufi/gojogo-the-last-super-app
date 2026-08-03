package com.gojogo;

import org.springframework.boot.web.error.ErrorAttributeOptions;
import org.springframework.boot.web.servlet.error.DefaultErrorAttributes;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.WebRequest;

import java.util.Map;

/**
 * Keeps the API's deliberate 4xx sentences and hushes everything a 5xx would say.
 *
 * <p>The app shows the server's own words — "you can withdraw up to…", "that
 * one's gone" — so {@code server.error.include-message} is left {@code always}
 * and those {@link org.springframework.web.server.ResponseStatusException}
 * reasons keep coming through on the {@code /error} render path.
 *
 * <p>The cost of {@code always} is that an <em>unexpected</em> 500 renders its
 * exception message too, and that message is a raw internal string — a
 * constraint name, a stack-trace fragment, the shape of a query. So this blanks
 * the {@code message} (and drops any error-class detail) for status 500 and up,
 * where there was never an intentional sentence to show, and leaves 4xx exactly
 * as before. Status codes are untouched: this only rewrites what the body says,
 * not what the response is.
 */
@Component
class SafeErrorAttributes extends DefaultErrorAttributes {

    private static final String GENERIC_5XX = "Something went wrong on our end.";

    @Override
    public Map<String, Object> getErrorAttributes(WebRequest request,
                                                  ErrorAttributeOptions options) {
        Map<String, Object> attributes = super.getErrorAttributes(request, options);
        Object status = attributes.get("status");
        if (status instanceof Integer code && code >= 500) {
            if (attributes.containsKey("message")) {
                attributes.put("message", GENERIC_5XX);
            }
            // Never let the exception class or trace ride out on a server fault.
            attributes.remove("trace");
            attributes.remove("exception");
        }
        return attributes;
    }
}
