@preconcurrency import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

protocol AuthenticationServicing: Sendable {
    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        displayName: String?
    ) async throws -> AuthenticatedAccount
    @MainActor func signInWithGoogle() async throws -> AuthenticatedAccount
    func deleteAccount(_ account: AuthenticatedAccount) async throws
}

struct FirebaseAuthenticationConfiguration: Sendable {
    let apiKey: String
    let authRequestURI: String
    let googleClientID: String?
    let googleCallbackScheme: String?

    static func fromBundle(_ bundle: Bundle = .main) -> FirebaseAuthenticationConfiguration? {
        guard let apiKey = bundle.object(forInfoDictionaryKey: "MileMateFirebaseAPIKey") as? String,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let authRequestURI = bundle.object(forInfoDictionaryKey: "MileMateFirebaseAuthRequestURI") as? String,
              !authRequestURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return FirebaseAuthenticationConfiguration(
            apiKey: apiKey,
            authRequestURI: authRequestURI,
            googleClientID: bundle.object(forInfoDictionaryKey: "MileMateGoogleClientID") as? String,
            googleCallbackScheme: bundle.object(forInfoDictionaryKey: "MileMateGoogleCallbackScheme") as? String
        )
    }
}

struct FirebaseAuthenticationService: AuthenticationServicing {
    private struct SignInResponse: Decodable {
        let localId: String
        let email: String?
        let displayName: String?
        let idToken: String
        let refreshToken: String
        let expiresIn: String
    }

    private struct ErrorEnvelope: Decodable {
        struct FirebaseError: Decodable { let message: String }
        let error: FirebaseError
    }

    private struct RefreshResponse: Decodable {
        let idToken: String

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    private let configuration: FirebaseAuthenticationConfiguration?
    private let session: URLSession

    init(
        configuration: FirebaseAuthenticationConfiguration? = .fromBundle(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        displayName: String?
    ) async throws -> AuthenticatedAccount {
        let response = try await signInWithIdentityProvider(
            providerID: "apple.com",
            idToken: identityToken,
            nonce: rawNonce,
            displayName: displayName
        )
        return account(from: response, provider: .apple, preferredName: displayName)
    }

    @MainActor
    func signInWithGoogle() async throws -> AuthenticatedAccount {
        guard let configuration else {
            throw AuthenticationError.configurationRequired(
                "Google sign-in requires Firebase and Google OAuth configuration."
            )
        }
        guard let clientID = configuration.googleClientID,
              let callbackScheme = configuration.googleCallbackScheme else {
            throw AuthenticationError.configurationRequired(
                "Add the Google client ID and callback URL scheme before using Google sign-in."
            )
        }
        let oauth = GoogleOAuthSession(clientID: clientID, callbackScheme: callbackScheme)
        let credential = try await oauth.authenticate()
        let response = try await signInWithIdentityProvider(
            providerID: "google.com",
            idToken: credential.idToken,
            nonce: nil,
            displayName: nil
        )
        return account(from: response, provider: .google, preferredName: nil)
    }

    func deleteAccount(_ account: AuthenticatedAccount) async throws {
        guard account.provider != .apple else {
            throw AuthenticationError.configurationRequired(
                "Apple account deletion requires secure server-side Apple token revocation before the Firebase user can be deleted."
            )
        }
        let configuration = try requiredConfiguration()
        let idToken = try await currentIDToken(for: account, configuration: configuration)
        let url = try endpoint("accounts:delete", apiKey: configuration.apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": idToken])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
               ["INVALID_ID_TOKEN", "TOKEN_EXPIRED", "USER_NOT_FOUND"].contains(envelope.error.message) {
                throw AuthenticationError.provider("Sign in again before deleting your account.")
            }
            throw AuthenticationError.provider("MileMate could not delete this account. Check your connection and try again.")
        }
    }

    private func currentIDToken(
        for account: AuthenticatedAccount,
        configuration: FirebaseAuthenticationConfiguration
    ) async throws -> String {
        guard account.tokenExpiration <= .now.addingTimeInterval(60) else { return account.idToken }
        guard let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(configuration.apiKey)") else {
            throw AuthenticationError.configurationRequired("The Firebase API configuration is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let refreshToken = account.refreshToken.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? account.refreshToken
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let refresh = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw AuthenticationError.provider("Sign in again before deleting your account.")
        }
        return refresh.idToken
    }

    private func signInWithIdentityProvider(
        providerID: String,
        idToken: String,
        nonce: String?,
        displayName: String?
    ) async throws -> SignInResponse {
        let configuration = try requiredConfiguration()
        let url = try endpoint("accounts:signInWithIdp", apiKey: configuration.apiKey)
        var postBody = "id_token=\(urlEncoded(idToken))&providerId=\(urlEncoded(providerID))"
        if let nonce { postBody += "&nonce=\(urlEncoded(nonce))" }
        var body: [String: Any] = [
            "postBody": postBody,
            "requestUri": configuration.authRequestURI,
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]
        if let displayName, !displayName.isEmpty { body["displayName"] = displayName }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw AuthenticationError.provider(envelope.error.message.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            throw AuthenticationError.provider("Authentication could not be completed.")
        }
        return try JSONDecoder().decode(SignInResponse.self, from: data)
    }

    private func account(
        from response: SignInResponse,
        provider: AuthenticationProvider,
        preferredName: String?
    ) -> AuthenticatedAccount {
        let lifetime = TimeInterval(response.expiresIn) ?? 3_600
        return AuthenticatedAccount(
            userID: response.localId,
            provider: provider,
            displayName: preferredName ?? response.displayName,
            email: response.email,
            idToken: response.idToken,
            refreshToken: response.refreshToken,
            tokenExpiration: .now.addingTimeInterval(lifetime),
            migratedGuestID: nil
        )
    }

    private func requiredConfiguration() throws -> FirebaseAuthenticationConfiguration {
        guard let configuration else {
            throw AuthenticationError.configurationRequired(
                "Authentication is not configured yet. Add the MileMate Firebase configuration in Xcode."
            )
        }
        return configuration
    }

    private func endpoint(_ method: String, apiKey: String) throws -> URL {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/\(method)?key=\(apiKey)") else {
            throw AuthenticationError.configurationRequired("The Firebase API configuration is invalid.")
        }
        return url
    }

    private func urlEncoded(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

@MainActor
private final class GoogleOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Credential { let idToken: String }

    private let clientID: String
    private let callbackScheme: String
    private var webSession: ASWebAuthenticationSession?

    init(clientID: String, callbackScheme: String) {
        self.clientID = clientID
        self.callbackScheme = callbackScheme
    }

    func authenticate() async throws -> Credential {
        let verifier = Self.randomURLSafeString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let state = Self.randomURLSafeString()
        let redirectURI = "\(callbackScheme):/oauthredirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authorizationURL = components.url else {
            throw AuthenticationError.configurationRequired("The Google OAuth configuration is invalid.")
        }
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthenticationError.canceled)
                } else if let error {
                    continuation.resume(throwing: AuthenticationError.provider(error.localizedDescription))
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthenticationError.invalidCredential)
                }
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            self.webSession = webSession
            webSession.start()
        }
        let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard callback?.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callback?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthenticationError.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let values = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        request.httpBody = values.map { pair in
            let (key, value) = pair
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encodedValue)"
        }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = object["id_token"] as? String else {
            throw AuthenticationError.provider("Google sign-in could not be completed.")
        }
        return Credential(idToken: idToken)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap { scene in scene.windows }
            .first { window in window.isKeyWindow } ?? ASPresentationAnchor()
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
