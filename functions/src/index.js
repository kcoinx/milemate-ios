"use strict";

const { initializeApp } = require("firebase-admin/app");
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

initializeApp();

const rateLimitSalt = defineSecret("FEEDBACK_RATE_LIMIT_SALT");

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
