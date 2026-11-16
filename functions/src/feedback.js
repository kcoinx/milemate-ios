"use strict";

const crypto = require("node:crypto");

const MAX_MESSAGE_LENGTH = 2_000;
const MAX_REQUEST_BYTES = 16_384;
const RATE_LIMIT_COUNT = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1_000;

class FeedbackValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "FeedbackValidationError";
    this.code = code;
  }
}

function isJSONContentType(contentType) {
  return typeof contentType === "string" &&
    contentType.toLowerCase().split(";", 1)[0].trim() === "application/json";
}

function validateFeedbackPayload(body, rawBodyLength = 0) {
  if (rawBodyLength > MAX_REQUEST_BYTES) {
    throw new FeedbackValidationError("request-too-large", "Request is too large.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new FeedbackValidationError("invalid-request", "Invalid request.");
  }

  const message = typeof body.message === "string" ? body.message.trim() : "";
  if (message.length < 10) {
    throw new FeedbackValidationError("message-too-short", "Feedback is too short.");
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new FeedbackValidationError("message-too-long", "Feedback is too long.");
  }
  if (body.website) {
    throw new FeedbackValidationError("invalid-request", "Invalid request.");
  }

  const submissionType = boundedString(
    body.submissionType,
    "submissionType",
    16,
    /^(feedback|support)$/,
  );
  const allowedCategories = submissionType === "feedback"
    ? new Set(["bug_report", "feature_suggestion", "general_feedback"])
    : new Set(["question", "help_request"]);
  const category = boundedString(body.category, "category", 32);
  if (!allowedCategories.has(category)) {
    throw new FeedbackValidationError("invalid-request", "Invalid category.");
  }

  let replyEmail = null;
  if (body.replyEmail !== undefined && body.replyEmail !== null && body.replyEmail !== "") {
    if (submissionType !== "support") {
      throw new FeedbackValidationError("invalid-request", "Invalid reply email.");
    }
    replyEmail = boundedString(body.replyEmail, "replyEmail", 254, EMAIL_PATTERN).toLowerCase();
  }

  return {
    message,
    submissionType,
    category,
    replyEmail,
    requestID: boundedString(body.requestID, "requestID", 36, UUID_PATTERN),
    appVersion: boundedString(body.appVersion, "appVersion", 32),
    build: boundedString(body.build, "build", 32),
    platform: boundedString(body.platform, "platform", 16, /^iOS$/),
  };
}

function boundedString(value, field, maximumLength, pattern) {
  if (typeof value !== "string") {
    throw new FeedbackValidationError("invalid-request", `Invalid ${field}.`);
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maximumLength || (pattern && !pattern.test(trimmed))) {
    throw new FeedbackValidationError("invalid-request", `Invalid ${field}.`);
  }
  return trimmed;
}

function rateLimitKey(ipAddress, salt) {
  if (!ipAddress || !salt) {
    throw new Error("Rate-limit configuration is unavailable.");
  }
  return crypto.createHmac("sha256", salt).update(ipAddress).digest("hex");
}

function nextRateLimitState(current, nowMilliseconds) {
  const currentWindow = current && Number.isFinite(current.windowStartedAt)
    ? current.windowStartedAt
    : 0;
  const currentCount = current && Number.isFinite(current.count) ? current.count : 0;
  const windowExpired = nowMilliseconds - currentWindow >= RATE_LIMIT_WINDOW_MS;

  if (!currentWindow || windowExpired) {
    return {
      allowed: true,
      state: { windowStartedAt: nowMilliseconds, count: 1 },
      retryAfterSeconds: 0,
    };
  }
  if (currentCount >= RATE_LIMIT_COUNT) {
    return {
      allowed: false,
      state: { windowStartedAt: currentWindow, count: currentCount },
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((currentWindow + RATE_LIMIT_WINDOW_MS - nowMilliseconds) / 1_000),
      ),
    };
  }
  return {
    allowed: true,
    state: { windowStartedAt: currentWindow, count: currentCount + 1 },
    retryAfterSeconds: 0,
  };
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

module.exports = {
  FeedbackValidationError,
  MAX_MESSAGE_LENGTH,
  MAX_REQUEST_BYTES,
  RATE_LIMIT_COUNT,
  RATE_LIMIT_WINDOW_MS,
  isJSONContentType,
  nextRateLimitState,
  rateLimitKey,
  validateFeedbackPayload,
};
