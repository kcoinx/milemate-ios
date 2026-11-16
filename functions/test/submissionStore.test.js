"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  SUPPORT_RETENTION_MS,
  persistSubmission,
} = require("../src/submissionStore");

test("persists a guest feedback submission without identity data", async () => {
  const firestore = new FakeFirestore();
  const result = await persistSubmission({
    firestore,
    rateKey: "hashed-network-key",
    submission: submission(),
    nowMilliseconds: 1_000,
    serverTimestamp: "SERVER_TIMESTAMP",
  });

  assert.deepEqual(result, { stored: true, duplicate: false, retryAfterSeconds: 0 });
  const stored = firestore.value("supportSubmissions/request-1");
  assert.equal(stored.type, "feedback");
  assert.equal(stored.category, "bug_report");
  assert.equal(stored.replyEmail, null);
  assert.equal(stored.createdAt, "SERVER_TIMESTAMP");
  assert.deepEqual(stored.expiresAt, new Date(1_000 + SUPPORT_RETENTION_MS));
  assert.equal("ipAddress" in stored, false);
  assert.equal("userID" in stored, false);
});

test("persists support questions and optional reply email", async () => {
  const firestore = new FakeFirestore();
  await persistSubmission({
    firestore,
    rateKey: "hashed-network-key",
    submission: submission({
      requestID: "support-1",
      submissionType: "support",
      category: "question",
      replyEmail: "person@example.com",
    }),
    nowMilliseconds: 1_000,
    serverTimestamp: "SERVER_TIMESTAMP",
  });

  const stored = firestore.value("supportSubmissions/support-1");
  assert.equal(stored.type, "support");
  assert.equal(stored.replyEmail, "person@example.com");
  assert.deepEqual(stored.expiresAt, new Date(1_000 + SUPPORT_RETENTION_MS));
});

test("sets support retention to exactly 365 days from receipt", async () => {
  const firestore = new FakeFirestore();
  const receivedAt = Date.UTC(2026, 10, 16, 12, 0, 0);
  await persistSubmission({
    firestore,
    rateKey: "hashed-network-key",
    submission: submission(),
    nowMilliseconds: receivedAt,
    serverTimestamp: "SERVER_TIMESTAMP",
  });

  const stored = firestore.value("supportSubmissions/request-1");
  assert.equal(
    stored.expiresAt.getTime() - receivedAt,
    365 * 24 * 60 * 60 * 1_000,
  );
});

test("duplicate request IDs return success without overwriting or consuming rate limit", async () => {
  const firestore = new FakeFirestore();
  const options = {
    firestore,
    rateKey: "hashed-network-key",
    submission: submission(),
    nowMilliseconds: 1_000,
    serverTimestamp: "SERVER_TIMESTAMP",
  };
  await persistSubmission(options);
  const original = firestore.value("supportSubmissions/request-1");
  const duplicate = await persistSubmission({
    ...options,
    submission: submission({ message: "A different message must not overwrite the first." }),
  });

  assert.deepEqual(duplicate, { stored: true, duplicate: true, retryAfterSeconds: 0 });
  assert.deepEqual(firestore.value("supportSubmissions/request-1"), original);
  assert.equal(firestore.value("_feedbackRateLimits/hashed-network-key").count, 1);
});

test("Firestore persistence enforces the shared rate limit", async () => {
  const firestore = new FakeFirestore();
  for (let index = 0; index < 5; index += 1) {
    const result = await persistSubmission({
      firestore,
      rateKey: "hashed-network-key",
      submission: submission({ requestID: `request-${index}` }),
      nowMilliseconds: 1_000 + index,
      serverTimestamp: "SERVER_TIMESTAMP",
    });
    assert.equal(result.stored, true);
  }
  const rejected = await persistSubmission({
    firestore,
    rateKey: "hashed-network-key",
    submission: submission({ requestID: "request-6" }),
    nowMilliseconds: 2_000,
    serverTimestamp: "SERVER_TIMESTAMP",
  });
  assert.equal(rejected.stored, false);
  assert.equal(firestore.value("supportSubmissions/request-6"), undefined);
});

function submission(overrides = {}) {
  return {
    requestID: "request-1",
    submissionType: "feedback",
    category: "bug_report",
    message: "A useful guest feedback message.",
    replyEmail: null,
    appVersion: "1.0",
    build: "28",
    platform: "iOS",
    ...overrides,
  };
}

class FakeFirestore {
  constructor() {
    this.documents = new Map();
  }

  collection(name) {
    return {
      doc: (id) => ({ path: `${name}/${id}` }),
    };
  }

  async runTransaction(operation) {
    const transaction = {
      get: async (reference) => ({
        exists: this.documents.has(reference.path),
        data: () => this.documents.get(reference.path),
      }),
      set: (reference, value) => {
        this.documents.set(reference.path, value);
      },
      create: (reference, value) => {
        if (this.documents.has(reference.path)) throw new Error("already exists");
        this.documents.set(reference.path, value);
      },
    };
    return operation(transaction);
  }

  value(path) {
    return this.documents.get(path);
  }
}
