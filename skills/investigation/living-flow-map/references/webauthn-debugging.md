# Example domain appendix: WebAuthn / passkey debugging

Generic WebAuthn (W3C Web Authentication, Level 2/3) facts for investigating passkey enrolment and
login failures. It contains no service-specific detail: record your own services' endpoints,
`file:line` anchors and config keys in the project's flow map, not here.

Authoritative sources: W3C Web Authentication spec (https://www.w3.org/TR/webauthn-3/) and
https://passkeys.dev.

## Glossary

- **Passkey:** a FIDO2 / WebAuthn credential (a public-private key pair) held by an authenticator
  (platform authenticator, security key, or a synced credential manager). The server stores only
  the public key and credential id.
- **Relying Party (RP):** the server side of the ceremony.
  - **RP ID:** a domain (no scheme, no port), e.g. `example.com`. Credentials are scoped to it.
  - **Origin:** scheme + host + port of the page running the ceremony, e.g.
    `https://login.example.com`.
- **Ceremony:** the two-step exchange for registration (enrol) or authentication (login).
- **Discoverable credential (resident key):** a credential the authenticator can find without the
  server naming it; needed for username-less login (empty `allowCredentials`).

## The two-step ceremony

Both registration and authentication are two round trips to the server:

| Step | Registration (enrol) | Authentication (login) |
|------|----------------------|------------------------|
| 1. Options | Server builds `PublicKeyCredentialCreationOptions` (challenge, RP, user entity, `pubKeyCredParams`, `excludeCredentials`, `authenticatorSelection`) and **stores the challenge** | Server builds `PublicKeyCredentialRequestOptions` (challenge, `rpId`, `allowCredentials`, `userVerification`) and **stores the challenge** |
| Browser | `navigator.credentials.create({ publicKey })` | `navigator.credentials.get({ publicKey })` |
| 2. Finish | Client posts the attestation response; server verifies it and stores the credential (id, public key, sign count) | Client posts the assertion; server verifies the signature against the stored public key |

What the server verifies in step 2 (per the spec):

- `clientDataJSON.type` is `webauthn.create` (registration) or `webauthn.get` (authentication).
- `clientDataJSON.challenge` equals the challenge it issued in step 1.
- `clientDataJSON.origin` is an expected origin.
- `authenticatorData.rpIdHash` equals SHA-256 of the RP ID.
- User Present flag is set; User Verified flag is set if user verification was required.
- Authentication only: the signature over `authenticatorData || SHA-256(clientDataJSON)` verifies
  with the stored public key for that credential id; the credential belongs to the user.

## The challenge is held between the two steps

- The challenge must be random (the spec requires at least 16 bytes), single-use and short-lived.
- It is commonly held in the server-side HTTP session. Consequences to check during an incident:
  - **Step 2 without step 1**, or step 1 on an expired/different session → "options / challenge
    not found". Check the session cookie is sent on both calls (`SameSite`, `Secure`, domain/path).
  - **Multiple instances** → the session store must be shared, or sessions must be sticky;
    otherwise step 2 lands on a node that never saw the challenge.
  - **Clear-after-use** → a well-behaved server deletes the challenge on the first step-2 attempt,
    so a client retry must restart from step 1. A retry that reuses old options fails by design.
  - **Timeout** → the `timeout` in the options and the server-side expiry should be consistent.

## RP ID and origin must match

- The RP ID must equal the page's effective domain or be a registrable suffix of it
  (`login.example.com` may use RP ID `example.com`, not `other.com`). It cannot be a public suffix.
- The page must be a secure context (HTTPS, or `http://localhost` for development).
- A mismatch makes the **browser** reject the call before anything reaches the server, typically
  with a `SecurityError` DOMException. Server logs will show step 1 but no step 2.
- A credential registered under one RP ID is not offered for a different RP ID. Changing the RP ID
  (or serving the flow from a new domain outside the suffix) makes existing passkeys unusable.
- The server's expected-origin list must include every origin that legitimately runs the ceremony
  (per environment, and native-app origins if applicable); otherwise server-side verification
  fails even though the browser succeeded.
- Cross-origin iframes need the `publickey-credentials-create` / `publickey-credentials-get`
  permissions policy.

## Common browser-side errors

- `NotAllowedError` — user cancelled, the operation timed out, or no matching credential was
  available (browsers deliberately do not distinguish these, for privacy).
- `InvalidStateError` on registration — the authenticator already holds a credential listed in
  `excludeCredentials` (already enrolled).
- `SecurityError` — RP ID not valid for the current origin, or insecure context.

## Server-side pitfalls

- **Encoding:** challenge, credential id and user handle are binary; JSON transport usually uses
  base64url without padding. Mixing base64 and base64url, or padding, breaks comparisons.
- **Sign count:** many passkeys (notably synced ones) always report `0`. Only treat a
  non-increasing count as a cloning signal when the stored count is non-zero.
- **User handle:** for discoverable-credential login the assertion carries `userHandle`; the server
  must map it to the user it set in `user.id` at registration.
- **Credential lookup:** "credential not found" on login usually means a different RP ID at
  registration, a deleted credential, or a lookup by the wrong key (credential id vs user handle).

## CSRF

If the ceremony endpoints use cookie-based sessions, their POST requests are subject to CSRF
protection. Many frameworks (for example Spring Security) enable it by default, so a missing or
stale CSRF token yields **403** on step 1 or step 2 before WebAuthn logic runs. Check how the
client obtains the token and that it is sent on every ceremony call.

## Async event publish without an outbox

A common design: after step 2 stores the credential, the service publishes a "credential
registered" event asynchronously so downstream services (e.g. a factor or account-security service)
can react. If the publish is fire-and-forget and there is no transactional outbox or retry:

- A publish failure after a successful store leaves the credential saved but **no event**
  emitted. The user can log in with the passkey, yet downstream state (e.g. "passkey enabled")
  never appears.
- Because the publish is asynchronous, the failure is usually only logged, not returned to the
  caller: the client sees success.
- Investigation: confirm the credential exists in the store, then look for the publish log line
  and the consumer's receipt, and confirm the producer and consumer agree on the channel name
  per environment.
- Record in the flow map how (or whether) such gaps are reconciled; if unknown, add it to
  **Open questions**.

## Debugging checklist (generic)

- Step 2 fails with "options/challenge not found" → session not carried between steps, expired,
  served by a different node, or options already consumed by an earlier attempt.
- Browser throws before the server sees step 2 → RP ID / origin mismatch or insecure context.
- Server verification fails on origin → expected-origin list missing this environment's origin.
- 403 on any ceremony call → CSRF token missing or stale.
- `InvalidStateError` on enrol → credential already registered.
- Login "credential not found" → RP ID changed since registration, credential deleted, or wrong
  lookup key.
- Enrol succeeds but downstream state never updates → async event not published or not consumed;
  check both ends and the channel name.
