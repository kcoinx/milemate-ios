# MileMate authentication setup

The app-side authentication and guest-trial implementation intentionally contains no credentials. Complete these steps before testing sign-in.

1. Create or select the production Firebase project and add the existing iOS app using the production MileMate bundle identifier.
2. In Firebase Authentication, enable Apple and Google providers. Do not enable automatic trip uploads; mileage remains local.
3. In Apple Developer, enable Sign in with Apple for the existing App ID and add the capability to the MileMate target. Regenerate the existing App Store provisioning profile if Apple requires it.
4. Configure the Apple provider in Firebase with the Apple team ID, Services ID, key ID, and private key from the production developer account.
5. Create an iOS Google OAuth client for the production bundle identifier and register its reversed client-ID callback scheme in the target's URL Types.
6. Supply these values through the production Xcode configuration or Info.plist substitution; never commit private configuration:
   - `MileMateFirebaseAPIKey`
   - `MileMateFirebaseAuthRequestURI` (an authorized Firebase auth-handler URI)
   - `MileMateGoogleClientID`
   - `MileMateGoogleCallbackScheme` (normally the reversed Google client ID)
7. Confirm the Firebase API key is restricted to the appropriate Apple app/API usage in Google Cloud Console.
8. Test Apple sign-in, Google sign-in, session restoration, sign-out, and account deletion on a physical iPhone before release.

Firebase Authentication establishes identity only. The current SwiftData mileage database remains local and is not advertised or treated as cloud-backed.
