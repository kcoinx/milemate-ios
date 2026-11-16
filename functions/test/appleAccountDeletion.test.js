"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const {
  AppleAccountDeletionError,
  appleClientSecret,
  bearerToken,
  validateDeletionPayload,
  verifyAppleIdentityToken,
} = require("../src/appleAccountDeletion");

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_CLIENT_ID = "com.fikrutibebe.milemate";

test("validates deletion authorization and request size", () => {
  assert.equal(bearerToken("Bearer firebase-token"), "firebase-token");
  assert.deepEqual(
    validateDeletionPayload({ authorizationCode: " apple-code " }, 100),
    { authorizationCode: "apple-code" },
  );
  assert.throws(
    () => validateDeletionPayload({ authorizationCode: "" }, 100),
    AppleAccountDeletionError,
  );
  assert.throws(
    () => validateDeletionPayload({ authorizationCode: "code" }, 40_000),
    (error) => error.code === "request-too-large" && error.status === 413,
  );
});

test("creates a short-lived ES256 Apple client secret", () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const token = appleClientSecret({
    teamID: "TEAM123",
    keyID: "KEY123",
    clientID: "com.fikrutibebe.milemate",
    privateKey: privateKey.export({ type: "pkcs8", format: "pem" }),
    nowSeconds: 1_700_000_000,
  });
  const [header, claims, signature] = token.split(".");
  assert.equal(
    crypto.verify(
      "sha256",
      Buffer.from(`${header}.${claims}`),
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(signature, "base64url"),
    ),
    true,
  );
  const decodedClaims = JSON.parse(
    Buffer.from(token.split(".")[1], "base64url").toString("utf8"),
  );
  assert.deepEqual(decodedClaims, {
    iss: "TEAM123",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    aud: "https://appleid.apple.com",
    sub: "com.fikrutibebe.milemate",
  });
});

async function signedAppleIdentityToken({
  privateKey,
  issuer = APPLE_ISSUER,
  audience = APPLE_CLIENT_ID,
  subject = "apple-user-123",
  expirationTime = "5m",
}) {
  const { SignJWT } = await import("jose");
  let token = new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: "apple-test-key" })
    .setIssuer(issuer)
    .setAudience(audience)
    .setSubject(subject)
    .setIssuedAt();
  if (expirationTime !== null) {
    token = token.setExpirationTime(expirationTime);
  }
  return token.sign(privateKey);
}

test("verifies a valid Apple identity token", async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const identityToken = await signedAppleIdentityToken({ privateKey });

  const claims = await verifyAppleIdentityToken({
    identityToken,
    clientID: APPLE_CLIENT_ID,
    keySet: publicKey,
  });

  assert.equal(claims.sub, "apple-user-123");
  assert.equal(claims.iss, APPLE_ISSUER);
  assert.equal(claims.aud, APPLE_CLIENT_ID);
});

test("rejects Apple identity tokens with an invalid signature", async () => {
  const signingKeys = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  const otherKeys = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  const identityToken = await signedAppleIdentityToken({
    privateKey: signingKeys.privateKey,
  });

  await assert.rejects(
    verifyAppleIdentityToken({
      identityToken,
      clientID: APPLE_CLIENT_ID,
      keySet: otherKeys.publicKey,
    }),
    (error) => error.code === "apple-response-invalid" && error.status === 502,
  );
});

test("rejects expired Apple identity tokens", async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const identityToken = await signedAppleIdentityToken({
    privateKey,
    expirationTime: Math.floor(Date.now() / 1_000) - 60,
  });

  await assert.rejects(
    verifyAppleIdentityToken({
      identityToken,
      clientID: APPLE_CLIENT_ID,
      keySet: publicKey,
    }),
    (error) => error.code === "apple-response-invalid",
  );
});

test("rejects Apple identity tokens without an expiration", async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const identityToken = await signedAppleIdentityToken({
    privateKey,
    expirationTime: null,
  });

  await assert.rejects(
    verifyAppleIdentityToken({
      identityToken,
      clientID: APPLE_CLIENT_ID,
      keySet: publicKey,
    }),
    (error) => error.code === "apple-response-invalid",
  );
});

test("rejects Apple identity tokens with the wrong issuer or audience", async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const wrongIssuer = await signedAppleIdentityToken({
    privateKey,
    issuer: "https://example.invalid",
  });
  const wrongAudience = await signedAppleIdentityToken({
    privateKey,
    audience: "com.example.other-app",
  });

  for (const identityToken of [wrongIssuer, wrongAudience]) {
    await assert.rejects(
      verifyAppleIdentityToken({
        identityToken,
        clientID: APPLE_CLIENT_ID,
        keySet: publicKey,
      }),
      (error) => error.code === "apple-response-invalid",
    );
  }
});
