import Foundation

/// Deployed backend + Cognito coordinates (see PROGRESS.md).
enum BackendConfig {
    static let apiBaseURL = URL(string: "https://f6kp8hx2j2.us-east-1.awsapprunner.com")!
    static let cognitoRegion = "us-east-1"
    static let cognitoClientId = "5gouehsu6bgaur82gcebiubvt0"
    static var cognitoEndpoint: URL {
        URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
    }

    // MARK: Hosted UI (Google federation)
    //
    // The Cognito Hosted UI domain hosts the OAuth endpoints the Google flow
    // uses. `hostedUIDomain` must match the deployed `authDomainPrefix` from
    // GojoGoAuthStack (CfnOutput `HostedUiDomain`); update it after deploy.
    static let hostedUIDomain = "gojogo-auth.auth.us-east-1.amazoncognito.com"
    static var hostedUIBaseURL: URL { URL(string: "https://\(hostedUIDomain)")! }

    /// Custom-scheme redirect registered as the app's OAuth callback. Must match
    /// the `callbackUrls` in GojoGoAuthStack's app client.
    static let oauthRedirectURI = "gojogo://auth/callback"
    static let oauthCallbackScheme = "gojogo"

    /// Apple's identity-token `aud` for a native sign-in is the app bundle id.
    /// The backend verifies against the same value (`APPLE_AUDIENCE`).
    static let appleAudience = "com.gojo.gojogo"

    // MARK: My World messaging WebSocket
    //
    // wss:// URL of the API Gateway WebSocket API (GojoGoMessagingStack output
    // `WebSocketUrl`). The client appends `?token=<Cognito ID token>`, which the
    // $connect authorizer validates. Fill in after the first messaging deploy.
    static let messagingSocketURL = "wss://ialc1dg00l.execute-api.us-east-1.amazonaws.com/prod"
}
