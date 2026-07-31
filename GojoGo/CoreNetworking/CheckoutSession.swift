import AuthenticationServices
import UIKit

/// Opens a Stripe-hosted page and waits for it to hand control back.
///
/// `ASWebAuthenticationSession` rather than a web view, for two reasons that
/// matter. It closes itself the moment the page redirects to `gojogo://`, which
/// is the only signal a hosted checkout gives that it's finished; and the page
/// runs outside the app's process, so the card details never pass through
/// anything this codebase wrote — which is the whole reason checkout is hosted.
///
/// Stripe refuses a custom URL scheme as a return target, so the redirect chain
/// is `Stripe → /v1/payments/return → gojogo://`, with that middle page served
/// by our own backend (see `PaymentsReturnController`).
///
/// Finishing here means "the customer came back", never "the payment
/// succeeded" — a browser reaching a URL proves nothing about money. The wallet
/// is credited by Stripe's signed webhook; the app just asks the server what
/// happened afterwards.
@MainActor
final class CheckoutSession: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum Outcome {
        /// The page redirected back into the app.
        case returned
        /// The customer dismissed the sheet. Not a failure — a payment may
        /// still land later, which is why the caller re-checks either way.
        case cancelled
    }

    private var session: ASWebAuthenticationSession?

    func present(_ url: URL) async -> Outcome {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: BackendConfig.oauthCallbackScheme
            ) { callbackURL, _ in
                continuation.resume(returning: callbackURL == nil ? .cancelled : .returned)
            }
            session.presentationContextProvider = self
            // A fresh session: a shared cookie jar buys nothing on a one-off
            // payment page and would leave the customer signed into Stripe's
            // domain afterwards.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                continuation.resume(returning: .cancelled)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { PresentationAnchor.keyWindow() }
    }
}
