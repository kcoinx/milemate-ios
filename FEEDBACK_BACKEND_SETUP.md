# MileMate feedback and support backend

MileMate stores feedback and support questions in the Firebase project `milemate-1df6d`. The Firebase-only backend is deployed; the commands below are retained for reviewed future deployments and must not be run merely because this document changed.

## 1. Confirm the Firebase project

From the repository root:

```powershell
firebase login
firebase use milemate-1df6d
firebase use
```

The last command must print `milemate-1df6d`. Stop if it prints another project. Deployment commands below include an explicit project flag as an additional safeguard.

## 2. Confirm Firestore

The default Firestore database must exist in `nam5`. Production-mode client rules must continue denying direct access to `supportSubmissions` and `_feedbackRateLimits`. The Cloud Function writes through Firebase Admin and does not require client access.

The repository's `firestore.rules` file denies every direct client read and write. Review it before any future rules deployment, then deploy only with explicit approval:

```powershell
firebase deploy --only firestore:rules --project milemate-1df6d
```

Configure Firestore TTL policies using the `expiresAt` field for both collection groups:

- `_feedbackRateLimits`: removes expired abuse-prevention records.
- `supportSubmissions`: makes each feedback or support submission eligible for deletion 365 days after it was received.

In Google Cloud Console, open Firestore → Time-to-live, create one policy for each collection group above, and select `expiresAt` as the timestamp field. Do not add an expiration offset because the function already writes the complete expiration timestamp.

Alternatively, after confirming the active gcloud project is `milemate-1df6d`, prepare each policy with:

```powershell
gcloud firestore fields ttls update expiresAt --collection-group=_feedbackRateLimits --database="(default)" --enable-ttl --project=milemate-1df6d
gcloud firestore fields ttls update expiresAt --collection-group=supportSubmissions --database="(default)" --enable-ttl --project=milemate-1df6d
gcloud firestore fields ttls list --database="(default)" --project=milemate-1df6d
```

TTL enablement can take time, and Firestore typically deletes expired documents within 24 hours after their expiration time. TTL deletion is not immediate.

### Existing submission backfill

Existing `supportSubmissions` documents without `expiresAt` are not affected by the TTL policy. Before relying on the 365-day policy:

1. Export or otherwise back up the collection according to the project's normal recovery procedure.
2. Count documents missing `expiresAt` and review a sample of their `createdAt` values.
3. Using a reviewed one-time Firebase Admin migration, set `expiresAt` to `createdAt + 365 days` only when `expiresAt` is absent. Process writes in bounded batches and do not change messages, reply addresses, status, or document IDs.
4. If a legacy document has no valid `createdAt`, decide and document a conservative expiration date before updating it; do not guess silently.
5. Run the migration in a dry-run/count-only mode first, then execute it only after approval.
6. Verify the updated count and inspect a sample before removing the migration tooling.

Documents whose backfilled expiration is already in the past become eligible for TTL deletion after the policy is active. Do not promise immediate removal.

### Early deletion requests

Early removal remains a manual, operator-only process; the iOS app receives no Firestore credentials:

1. Accept the request through `kcoinx@gmail.com` or the in-app Contact Support form.
2. Ask only for the approximate submission date, submission type/category, optional reply email used, and a short non-sensitive phrase from the message. Never request passwords, authentication tokens, payment details, or trip coordinates.
3. From an authorized Firebase administrator account, locate candidate documents in `supportSubmissions` using the supplied details. Verify a single match before deleting anything. If ownership or the matching record cannot be established, explain that safely rather than deleting a different submission.
4. Delete only the confirmed submission document. Do not delete rate-limit records, authentication accounts, mileage data, or unrelated support records.
5. Confirm completion to the requester without copying the original message into email or logs. Keep only the minimum operational record required to document that the request was handled.

Account deletion does not automatically delete support submissions, and deleting a support submission does not delete an account or cancel an App Store subscription.

## 3. Configure the one required secret

Generate a long random value with a password manager. Do not reuse a password and do not save the value in this repository.

```powershell
firebase functions:secrets:set FEEDBACK_RATE_LIMIT_SALT --project milemate-1df6d
```

Firebase prompts for the value securely. No email-provider or recipient secrets are required.

## 4. Test locally

```powershell
npm --prefix functions install
npm --prefix functions test
firebase emulators:start --only functions,firestore --project milemate-1df6d
```

Do not store production secrets in committed `.env` files.

## 5. Deploy after approval

```powershell
firebase deploy --only functions:submitFeedback --project milemate-1df6d
```

After deployment, confirm the HTTPS URL matches `MileMateFeedbackEndpoint` in `MileMate/Info.plist`. Submit one feedback message and one support question from a test build, then verify both documents in Firestore.

After the Firebase-only function is deployed and verified, remove the three obsolete email-delivery secrets if they exist. Run each command separately and confirm the prompt:

```powershell
firebase functions:secrets:destroy RESEND_API_KEY --project milemate-1df6d
firebase functions:secrets:destroy FEEDBACK_RECIPIENT_EMAIL --project milemate-1df6d
firebase functions:secrets:destroy FEEDBACK_FROM_EMAIL --project milemate-1df6d
```

Do not remove `FEEDBACK_RATE_LIMIT_SALT`.

## Firestore structure

Each document is stored at `supportSubmissions/{requestID}` with:

- `type`: `feedback` or `support`
- `category`: the selected feedback/support category
- `message`: validated user-entered text
- `replyEmail`: optional and available only for support submissions
- `app`: app version, build, and platform
- `status`: initially `new`
- `createdAt`: Firestore server timestamp
- `expiresAt`: receipt time plus 365 days; used by the `supportSubmissions` TTL policy

The request ID is used as the document ID, so retries cannot create duplicates or overwrite an existing submission.

## Security controls

- POST and `application/json` are required.
- Requests are limited to 16 KiB.
- Messages are trimmed and limited to 10–2,000 characters on the client and server.
- Type, category, reply email, request ID, and app metadata are validated server-side.
- A honeypot field is rejected when populated.
- A Firestore transaction atomically applies rate limiting and creates the submission.
- Each HMAC-hashed network address is limited to five new submissions per hour.
- Raw network addresses are never stored.
- Messages and reply addresses are never written to function logs or responses.
- Firebase Admin performs all writes; the iOS app receives no Firestore credentials or direct collection access.

For stronger device attestation later, add Firebase App Check with App Attest to the iOS target and enforce its token in the function. That requires a separate reviewed Firebase Apple SDK integration.
