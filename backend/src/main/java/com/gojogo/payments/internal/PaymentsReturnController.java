package com.gojogo.payments.internal;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Where Stripe sends the customer's browser when a hosted page is finished.
 *
 * <p>This page exists for one structural reason: Stripe Checkout and Connect
 * onboarding both refuse a custom URL scheme as a return target, and the app
 * needs to be handed back control. So the round trip goes
 * {@code app → Stripe → this page → gojogo://}, and an
 * {@code ASWebAuthenticationSession} watching for the scheme closes itself the
 * moment the redirect fires.
 *
 * <p>It is deliberately inert. It reads no session, credits nothing, and tells
 * the visitor nothing about an account — arriving here proves only that a
 * browser arrived here. The wallet is credited by the signed webhook; this page
 * just gets the customer home.
 */
@RestController
class PaymentsReturnController {

    private static final String APP_SCHEME_URL = "gojogo://payments/return";

    @GetMapping(path = "/v1/payments/return", produces = MediaType.TEXT_HTML_VALUE)
    ResponseEntity<String> returned(@RequestParam(defaultValue = "") String status) {
        String heading = switch (status) {
            case "success" -> "Payment received";
            case "cancelled" -> "Payment cancelled";
            case "connected" -> "Payouts set up";
            default -> "All done";
        };
        String detail = "success".equals(status)
            ? "Your wallet will update in a moment."
            : "You can close this window and go back to GoJoGo.";

        // The redirect is attempted immediately and the page still reads
        // correctly if it doesn't fire — an in-app browser that blocks scheme
        // navigation should leave a person with a sentence, not a blank screen.
        String html = """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>GoJoGo</title>
              <style>
                body { font: -apple-system-body, system-ui, sans-serif; margin: 0;
                       min-height: 100vh; display: grid; place-items: center;
                       background: #0b0b0f; color: #f5f5f7; text-align: center; padding: 24px; }
                h1 { font-size: 22px; margin: 0 0 8px; }
                p  { margin: 0; opacity: .7; font-size: 15px; }
                a  { color: #7aa2ff; display: inline-block; margin-top: 24px; }
              </style>
            </head>
            <body>
              <main>
                <h1>%s</h1>
                <p>%s</p>
                <a href="%s">Return to GoJoGo</a>
              </main>
              <script>location.replace(%s);</script>
            </body>
            </html>
            """.formatted(heading, detail, APP_SCHEME_URL, "'" + APP_SCHEME_URL + "'");
        return ResponseEntity.ok().body(html);
    }
}
