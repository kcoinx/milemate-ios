"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  FeedbackValidationError,
  MAX_MESSAGE_LENGTH,
  RATE_LIMIT_COUNT,
  RATE_LIMIT_WINDOW_MS,
  isJSONContentType,
  nextRateLimitState,
  rateLimitKey,
  validateFeedbackPayload,
} = require("../src/feedback");

function validPayload(overrides = {}) {
  return {
    message: "The automatic tracking experience worked well.",
    submissionType: "feedback",
    category: "general_feedback",
    requestID: "812a8f4a-b012-4a7d-9b24-447fce269d77",
    appVersion: "1.0",
    build: "28",
    platform: "iOS",
    ...overrides,
  };
}

test("accepts JSON content types with an optional charset", () => {
  assert.equal(isJSONContentType("application/json"), true);
  assert.equal(isJSONContentType("application/json; charset=utf-8"), true);
  assert.equal(isJSONContentType("text/plain"), false);
});

test("validates and trims a guest feedback payload", () => {
  const result = validateFeedbackPayload(validPayload({ message: "  Useful feedback message  " }), 200);
  assert.equal(result.message, "Useful feedback message");
  assert.equal(result.platform, "iOS");
  assert.equal(result.replyEmail, null);
});

test("validates support questions with an optional reply email", () => {
  const result = validateFeedbackPayload(validPayload({
    submissionType: "support",
    category: "help_request",
    replyEmail: " Person@Example.com ",
  }));
  assert.equal(result.submissionType, "support");
  assert.equal(result.replyEmail, "person@example.com");
});

test("rejects oversized feedback and request bodies", () => {
  assert.throws(
    () => validateFeedbackPayload(validPayload({ message: "a".repeat(MAX_MESSAGE_LENGTH + 1) })),
    (error) => error instanceof FeedbackValidationError && error.code === "message-too-long",
  );
  assert.throws(
    () => validateFeedbackPayload(validPayload(), 20_000),
    (error) => error instanceof FeedbackValidationError && error.code === "request-too-large",
  );
});

test("rejects invalid metadata and honeypot submissions", () => {
  assert.throws(() => validateFeedbackPayload(validPayload({ platform: "web" })));
  assert.throws(() => validateFeedbackPayload(validPayload({ website: "spam.example" })));
  assert.throws(() => validateFeedbackPayload(validPayload({ requestID: "not-a-uuid" })));
  assert.throws(() => validateFeedbackPayload(validPayload({ category: "help_request" })));
  assert.throws(() => validateFeedbackPayload(validPayload({
    submissionType: "support",
    category: "question",
    replyEmail: "not-an-email",
  })));
});

test("rate limiter permits five requests and rejects the sixth", () => {
  const startedAt = 1_000_000;
  let state;
  for (let count = 0; count < RATE_LIMIT_COUNT; count += 1) {
    const result = nextRateLimitState(state, startedAt + count);
    assert.equal(result.allowed, true);
    state = result.state;
  }
  const rejected = nextRateLimitState(state, startedAt + 10);
  assert.equal(rejected.allowed, false);
  assert.ok(rejected.retryAfterSeconds > 0);

  const reset = nextRateLimitState(state, startedAt + RATE_LIMIT_WINDOW_MS);
  assert.equal(reset.allowed, true);
  assert.equal(reset.state.count, 1);
});

test("rate-limit keys are stable hashes and do not expose the IP", () => {
  const first = rateLimitKey("203.0.113.10", "test-secret");
  const second = rateLimitKey("203.0.113.10", "test-secret");
  assert.equal(first, second);
  assert.equal(first.includes("203.0.113.10"), false);
  assert.equal(first.length, 64);
});
