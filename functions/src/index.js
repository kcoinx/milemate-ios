"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");
const {
  FeedbackValidationError,
  isJSONContentType,
  rateLimitKey,
  validateFeedbackPayload,
} = require("./feedback");
const { persistSubmission } = require("./submissionStore");
const {
  AppleAccountDeletionError,
  appleClientSecret,
  bearerToken,
  exchangeAuthorizationCode,
  revokeAppleToken,
  validateDeletionPayload,
  verifyAppleIdentityToken,
} = require("./appleAccountDeletion");

initializeApp();

const rateLimitSalt = defineSecret("FEEDBACK_RATE_LIMIT_SALT");
const appleTeamID = defineSecret("APPLE_TEAM_ID");
const appleKeyID = defineSecret("APPLE_KEY_ID");
const appleClientID = defineSecret("APPLE_CLIENT_ID");
const applePrivateKey = defineSecret("APPLE_PRIVATE_KEY");

exports.submitFeedback = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
    maxInstances: 5,
    cors: false,
    secrets: [rateLimitSalt],
  },
  async (request, response) => {
    response.set("Cache-Control", "no-store");
    response.set("X-Content-Type-Options", "nosniff");

    if (request.method !== "POST") {
      response.set("Allow", "POST");
      response.status(405).json({ stored: false, code: "method-not-allowed" });
      return;
    }
    if (!isJSONContentType(request.get("content-type"))) {
      response.status(415).json({ stored: false, code: "unsupported-media-type" });
      return;
    }

    let feedback;
    try {
      feedback = validateFeedbackPayload(request.body, request.rawBody?.length ?? 0);
    } catch (error) {
      if (error instanceof FeedbackValidationError) {
        const status = error.code === "request-too-large" ? 413 : 400;
        response.status(status).json({ stored: false, code: error.code });
        return;
      }
      response.status(400).json({ stored: false, code: "invalid-request" });
      return;
    }

    const ipAddress = request.ip;
    if (!ipAddress) {
      response.status(400).json({ stored: false, code: "invalid-request" });
      return;
    }

    try {
      const result = await persistSubmission({
        firestore: getFirestore(),
        rateKey: rateLimitKey(ipAddress, rateLimitSalt.value()),
        submission: feedback,
        nowMilliseconds: Date.now(),
        serverTimestamp: FieldValue.serverTimestamp(),
      });
      if (!result.stored) {
        response.set("Retry-After", String(result.retryAfterSeconds));
        response.status(429).json({ stored: false, code: "rate-limited" });
        return;
      }
      response.status(200).json({ stored: true, duplicate: result.duplicate });
    } catch {
      console.error("Support submission persistence failed.");
      response.status(500).json({ stored: false, code: "storage-failed" });
    }
  },
);

exports.deleteAppleAccount = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
    maxInstances: 5,
    cors: false,
    secrets: [appleTeamID, appleKeyID, appleClientID, applePrivateKey],
  },
  async (request, response) => {
    response.set("Cache-Control", "no-store");
    response.set("X-Content-Type-Options", "nosniff");
    if (request.method !== "POST") {
      response.set("Allow", "POST");
      response.status(405).json({ deleted: false, code: "method-not-allowed" });
      return;
    }
    if (!isJSONContentType(request.get("content-type"))) {
      response.status(415).json({ deleted: false, code: "unsupported-media-type" });
      return;
    }

    try {
      const firebaseToken = bearerToken(request.get("authorization"));
      const { authorizationCode } = validateDeletionPayload(
        request.body,
        request.rawBody?.length ?? 0,
      );
      const auth = getAuth();
      const verifiedToken = await auth.verifyIdToken(firebaseToken, true);
      const user = await auth.getUser(verifiedToken.uid);
      const appleProvider = user.providerData.find((provider) =>
        provider.providerId === "apple.com");
      if (!appleProvider?.uid) {
        throw new AppleAccountDeletionError("apple-account-required", 403);
      }

      const clientID = appleClientID.value().trim();
      const clientSecret = appleClientSecret({
        teamID: appleTeamID.value(),
        keyID: appleKeyID.value(),
        clientID,
        privateKey: applePrivateKey.value(),
      });
      const appleTokens = await exchangeAuthorizationCode({
        authorizationCode,
        clientID,
        clientSecret,
        fetchImpl: fetch,
      });
      const appleIdentity = await verifyAppleIdentityToken({
        identityToken: appleTokens.id_token,
        clientID,
      });
      if (appleIdentity.sub !== appleProvider.uid) {
        throw new AppleAccountDeletionError("account-mismatch", 403);
      }

      await revokeAppleToken({
        refreshToken: appleTokens.refresh_token,
        clientID,
        clientSecret,
        fetchImpl: fetch,
      });
      await auth.deleteUser(verifiedToken.uid);
      response.status(200).json({ deleted: true });
    } catch (error) {
      if (error instanceof AppleAccountDeletionError) {
        response.status(error.status).json({ deleted: false, code: error.code });
        return;
      }
      console.error("Apple account deletion failed without exposing account data.");
      response.status(500).json({ deleted: false, code: "deletion-failed" });
    }
  },
);
