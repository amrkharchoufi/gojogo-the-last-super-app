import Foundation

/// Deployed backend + Cognito coordinates (see PROGRESS.md).
enum BackendConfig {
    static let apiBaseURL = URL(string: "https://f6kp8hx2j2.us-east-1.awsapprunner.com")!
    static let cognitoRegion = "us-east-1"
    static let cognitoClientId = "5gouehsu6bgaur82gcebiubvt0"
    static var cognitoEndpoint: URL {
        URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
    }
}
