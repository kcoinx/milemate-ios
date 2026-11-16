"use strict";

const crypto = require("node:crypto");

const MAX_REQUEST_BYTES = 32_768;
const APPLE_AUDIENCE = "https://appleid.apple.com";
const APPLE_JWKS_URL = new URL("https://appleid.apple.com/auth/keys");
let appleJWKS;

class AppleAccountDeletionError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "AppleAccountDeletionError";
    this.code = code;
    this.status = status;
  }
}

function bearerToken(authorizationHeader) {
  if (typeof authorizationHeader !== "string") {
    throw new AppleAccountDeletionError("authentication-required", 401);
  }
  const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  if (!match || match[1].length > 8_192) {
    throw new AppleAccountDeletionError("authentication-required", 401);
  }
  return match[1];
}

function validateDeletionPayload(body, rawBodyLength = 0) {
  if (rawBodyLength > MAX_REQUEST_BYTES) {
    throw new AppleAccountDeletionError("request-too-large", 413);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new AppleAccountDeletionError("invalid-request");
  }
  const authorizationCode = typeof body.authorizationCode === "string"
    ? body.authorizationCode.trim()
    : "";
  if (!authorizationCode || authorizationCode.length > 8_192) {
    throw new AppleAccountDeletionError("invalid-request");
  }
  return { authorizationCode };
}

function base64URL(value) {
  return Buffer.from(value).toString("base64url");
}

function appleClientSecret({ teamID, keyID, clientID, privateKey, nowSeconds }) {
  if (![teamID, keyID, clientID, privateKey].every((value) =>
    typeof value === "string" && value.trim().length > 0)) {
    throw new AppleAccountDeletionError("server-configuration-error", 500);
  }
  const issuedAt = Math.floor(nowSeconds ?? Date.now() / 1_000);
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID.trim() }));
  const claims = base64URL(JSON.stringify({
    iss: teamID.trim(),
    iat: issuedAt,
    exp: issuedAt + 300,
    aud: APPLE_AUDIENCE,
    sub: clientID.trim(),
  }));
  const signingInput = `${header}.${claims}`;
  const normalizedKey = privateKey.replace(/\\n/g, "\n");
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: normalizedKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${signature.toString("base64url")}`;
}

async function verifyAppleIdentityToken({ identityToken, clientID, keySet }) {
  if (typeof identityToken !== "string" || !identityToken ||
      typeof clientID !== "string" || !clientID.trim()) {
    throw new AppleAccountDeletionError("apple-response-invalid", 502);
  }
  try {
    const { createRemoteJWKSet, jwtVerify } = await import("jose");
    if (!keySet) {
      appleJWKS ??= createRemoteJWKSet(APPLE_JWKS_URL);
    }
    const { payload } = await jwtVerify(identityToken, keySet ?? appleJWKS, {
      algorithms: ["RS256"],
      issuer: APPLE_AUDIENCE,
      audience: clientID.trim(),
    });
    if (typeof payload.sub !== "string" || !payload.sub ||
        typeof payload.exp !== "number") {
      throw new Error("Missing required Apple identity claims");
    }
    return payload;
  } catch {
    throw new AppleAccountDeletionError("apple-response-invalid", 502);
  }
}

async function exchangeAuthorizationCode({ authorizationCode, clientID, clientSecret, fetchImpl }) {
  const body = new URLSearchParams({
    client_id: clientID,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  const response = await fetchImpl("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || typeof result.refresh_token !== "string" ||
      typeof result.id_token !== "string") {
    throw new AppleAccountDeletionError("apple-authorization-failed", 400);
  }
  return result;
}

async function revokeAppleToken({ refreshToken, clientID, clientSecret, fetchImpl }) {
  const body = new URLSearchParams({
    client_id: clientID,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  const response = await fetchImpl("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) {
    throw new AppleAccountDeletionError("apple-revocation-failed", 502);
  }
}

module.exports = {
  AppleAccountDeletionError,
  appleClientSecret,
  bearerToken,
  exchangeAuthorizationCode,
  revokeAppleToken,
  validateDeletionPayload,
  verifyAppleIdentityToken,
};
