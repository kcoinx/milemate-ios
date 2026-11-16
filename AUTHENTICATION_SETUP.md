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

## Apple account deletion

MileMate's iOS app obtains a fresh Apple authorization code and sends it with the signed-in user's Firebase ID token to the `deleteAppleAccount` HTTPS function. The function verifies the Firebase user and Apple provider identity, exchanges the one-time code with Apple, revokes the returned Apple refresh token, and only then deletes the Firebase Authentication user. Apple private keys never belong in the app, Info.plist, or Git.

Before the function can be deployed, configure these Firebase function secrets from the matching Apple Developer account:

```powershell
firebase functions:secrets:set APPLE_TEAM_ID --project milemate-1df6d
firebase functions:secrets:set APPLE_KEY_ID --project milemate-1df6d
firebase functions:secrets:set APPLE_CLIENT_ID --project milemate-1df6d
firebase functions:secrets:set APPLE_PRIVATE_KEY --project milemate-1df6d
```

- `APPLE_TEAM_ID`: the Apple Developer Team ID.
- `APPLE_KEY_ID`: the identifier of a Sign in with Apple key authorized for the MileMate App ID.
- `APPLE_CLIENT_ID`: `com.fikrutibebe.milemate` for MileMate's native Apple authorization-code flow. Confirm this value against the production App ID before deployment.
- `APPLE_PRIVATE_KEY`: the complete `.p8` key contents entered only at the Firebase CLI secret prompt. Do not save it in a repository file or shell history.

After explicit approval, deploy only the new function:

```powershell
firebase deploy --only functions:deleteAppleAccount --project milemate-1df6d
```

Confirm the deployed URL is exactly the HTTPS value configured as `MileMateAppleAccountDeletionEndpoint` in `MileMate/Info.plist`. Test successful deletion and canceled/expired authorization on a physical iPhone. Also verify in Apple Account settings that the app authorization is revoked and in Firebase Authentication that the user is removed.

Firebase Authentication establishes identity only. The current SwiftData mileage database remains local and is not advertised or treated as cloud-backed.
