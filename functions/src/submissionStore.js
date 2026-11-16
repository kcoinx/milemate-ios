"use strict";

const { nextRateLimitState } = require("./feedback");

async function persistSubmission({
  firestore,
  rateKey,
  submission,
  nowMilliseconds,
  serverTimestamp,
}) {
  const submissionReference = firestore
    .collection("supportSubmissions")
    .doc(submission.requestID);
  const rateReference = firestore
    .collection("_feedbackRateLimits")
    .doc(rateKey);

  return firestore.runTransaction(async (transaction) => {
    const [submissionSnapshot, rateSnapshot] = await Promise.all([
      transaction.get(submissionReference),
      transaction.get(rateReference),
    ]);

    if (submissionSnapshot.exists) {
      return { stored: true, duplicate: true, retryAfterSeconds: 0 };
    }

    const currentRate = rateSnapshot.exists ? rateSnapshot.data() : undefined;
    const limit = nextRateLimitState(currentRate, nowMilliseconds);
    if (!limit.allowed) {
      return {
        stored: false,
        duplicate: false,
        retryAfterSeconds: limit.retryAfterSeconds,
      };
    }

    transaction.set(
      rateReference,
      {
        ...limit.state,
        expiresAt: new Date(limit.state.windowStartedAt + 24 * 60 * 60 * 1_000),
        updatedAt: serverTimestamp,
      },
      { merge: true },
    );
    transaction.create(submissionReference, {
      type: submission.submissionType,
      category: submission.category,
      message: submission.message,
      replyEmail: submission.replyEmail,
      app: {
        version: submission.appVersion,
        build: submission.build,
        platform: submission.platform,
      },
      status: "new",
      createdAt: serverTimestamp,
    });

    return { stored: true, duplicate: false, retryAfterSeconds: 0 };
  });
}

module.exports = { persistSubmission };
