import Foundation

/// Native Cognito auth over its JSON API — no Amplify dependency.
struct CognitoAuthClient {

    struct Tokens {
        var idToken: String
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int
    }

    enum AuthError: LocalizedError {
        case cognito(type: String, message: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .cognito(let type, let message):
                switch type {
                case "UsernameExistsException": return "That email already has an account."
                case "NotAuthorizedException": return "Wrong email or password."
                case "UserNotFoundException": return "No account with that email yet."
                case "CodeMismatchException": return "That code doesn't match — try again."
                case "ExpiredCodeException": return "That code expired — we sent a new one."
                case "InvalidPasswordException": return "Password needs 8+ characters incl. a number."
                case "UserNotConfirmedException": return "Account not confirmed yet — check your email."
                case "LimitExceededException", "TooManyRequestsException": return "Too many attempts — wait a minute."
                default: return message.isEmpty ? type : message
                }
            case .malformedResponse:
                return "Unexpected response from sign-in service."
            }
        }

        var cognitoType: String? {
            if case .cognito(let type, _) = self { return type }
            return nil
        }
    }

    /// Returns the Cognito user sub.
    @discardableResult
    func signUp(email: String, password: String) async throws -> String {
        let response = try await call("SignUp", body: [
            "ClientId": BackendConfig.cognitoClientId,
            "Username": email,
            "Password": password,
            "UserAttributes": [["Name": "email", "Value": email]],
        ])
        guard let sub = response["UserSub"] as? String else { throw AuthError.malformedResponse }
        return sub
    }

    func confirmSignUp(email: String, code: String) async throws {
        _ = try await call("ConfirmSignUp", body: [
            "ClientId": BackendConfig.cognitoClientId,
            "Username": email,
            "ConfirmationCode": code,
        ])
    }

    func resendConfirmationCode(email: String) async throws {
        _ = try await call("ResendConfirmationCode", body: [
            "ClientId": BackendConfig.cognitoClientId,
            "Username": email,
        ])
    }

    func signIn(email: String, password: String) async throws -> Tokens {
        let response = try await call("InitiateAuth", body: [
            "ClientId": BackendConfig.cognitoClientId,
            "AuthFlow": "USER_PASSWORD_AUTH",
            "AuthParameters": ["USERNAME": email, "PASSWORD": password],
        ])
        return try tokens(from: response)
    }

    func refresh(refreshToken: String) async throws -> Tokens {
        let response = try await call("InitiateAuth", body: [
            "ClientId": BackendConfig.cognitoClientId,
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "AuthParameters": ["REFRESH_TOKEN": refreshToken],
        ])
        return try tokens(from: response)
    }

    private func tokens(from response: [String: Any]) throws -> Tokens {
        guard let result = response["AuthenticationResult"] as? [String: Any],
              let idToken = result["IdToken"] as? String,
              let accessToken = result["AccessToken"] as? String
        else { throw AuthError.malformedResponse }
        return Tokens(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: result["RefreshToken"] as? String,
            expiresIn: result["ExpiresIn"] as? Int ?? 3600)
    }

    private func call(_ action: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: BackendConfig.cognitoEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(action)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse else { throw AuthError.malformedResponse }
        if http.statusCode != 200 {
            let rawType = (json["__type"] as? String) ?? "UnknownError"
            let type = rawType.components(separatedBy: "#").last ?? rawType
            let message = (json["message"] as? String) ?? (json["Message"] as? String) ?? ""
            throw AuthError.cognito(type: type, message: message)
        }
        return json
    }
}
