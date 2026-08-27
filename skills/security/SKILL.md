---
name: security
description: SAML, OAuth, SSL/TLS, LDAP, ZAUTHENTICATE. Routed from interop. Triggers: SAML, OAuth 2.0, OAuth, SSL/TLS, certificate, LDAP, ZAUTHENTICATE, PKCE, seguridad, autenticación, certificado.
---

# Security on IRIS Interop endpoints

Security work on IRIS Interop splits into three operational concerns: **identity assertions** (SAML), **authorization flows** (OAuth 2.0), and **transport** (SSL/TLS, plus internal account hygiene). Pick the section that matches the user's question.

## When to use this skill

The user mentioned SAML, OAuth, an SSL/TLS certificate chain, ZAUTHENTICATE, the `CSPSystem` account, or the IRIS Initial Security level. For OAuth 2.0 + PKCE on a FHIR Façade, also load `fhir`.

## SAML 2.0

### Use the SAML-COS ObjectScript implementation, not native `%SAML`

Native `%SAML.Assertion` has a known charset bug: any non-Latin-1 character in the assertion (a `€` sign, accented Catalan/Spanish letters, etc.) produces an invalid signature, rejected by strict validators with errors like `"signature not valid"`. Latin-1-only assertions sign correctly, which makes the bug intermittent and hard to diagnose.

**Use** the public `intersystems-ib/SAML-COS` package — built specifically to address this issue and the standard for new SAML 2.0 work.

Older workarounds (generating the SAML assertion via external Java code through JavaGateway) are superseded; only resurrect them if the customer is on an IRIS version SAML-COS doesn't support.

### The assertion must be self-contained

When the SAML assertion is carried as a SOAP `wsse:Security` header, it must declare all its own XML namespaces and prefixes. The receiver extracts the assertion from the SOAP envelope and processes it in isolation — the parent envelope's `xmlns:` declarations are no longer visible.

If the assertion is generated inside SOAP-envelope-aware code that inherits namespaces from the envelope, the signature breaks once the assertion is extracted standalone. The same constraint applies to SAML 1.1.

**Verify** before integration: extract the SAML assertion from a captured request, paste it as a standalone document, and confirm the signature still validates.

### Custom security header on a generated SOAP BO

When attaching a SAML assertion to a SOAP BO call, instantiate the SOAP web client manually so the security header can be set per-request:

```objectscript
Set ..Adapter.WebServiceClientClass = "<package>.<GeneratedClient>"
Set ..Adapter.%Client = $classmethod(..Adapter.WebServiceClientClass, "%New")

Set tSC = ..GenSecurityHeader(pRequest.atributosSAML, .tHeader)
Quit:$$$ISERR(tSC) tSC
Set ..Adapter.%Client.SecurityOut = tHeader

Set tSC = ..Adapter.InvokeMethod("methodName", .tResponse, ...)
```

Expose an X.509 `SAMLCredentials` BO setting that aliases an IRIS credentials configuration. This decouples the signing certificate from the code so the cert can be rotated per-environment without redeployment.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch11_security/saml2-custom-security-header.cls`.

## SAML 1.1

Native `%SAML` is SAML 2.0 only. If the partner system requires SAML 1.1 (older Catalan public-sector services and some legacy enterprise integrations), use the public `intersystems-ib/SAML11-COS` package.

Key differences from SAML 2.0 the package handles:

- Namespace `urn:oasis:names:tc:SAML:1.0:assertion`.
- `AssertionID` attribute instead of `ID`.
- `MajorVersion` / `MinorVersion` instead of `Version`.
- `Issuer` is a string attribute, not a `NameID` child element.
- Subject lives inside `StatementList`, not at the assertion root.
- `%XML.Security.Signature` is cloned so `GetNodeById` matches `AssertionID` instead of `ID`.

Two integration-time pitfalls to watch:

- **GUID-style AssertionIDs are rejected** by some SAML 1.1 validators — use a fixed-format ID like `_23f8a4ad91cd56ff7715912dd6ab072f`.
- **Suppress the `xsi:type` attribute** in `SAML11.AttributeValue` — emitting it triggers a 1.1 validation error on strict receivers.

## OAuth 2.0

### Server-side OAuth 2.0 with LDAP back-end

Use IRIS as an OAuth 2.0 broker between a third-party SaaS app and on-premise Active Directory:

1. Configure the OAuth 2.0 Server in Portal: `System Administration → Security → OAuth 2.0 → Server`. Grant type: `Authorization Code Grant`.
2. Set the customisation namespace to the interop namespace.
3. Provide two custom subclasses:
   - `OAuth2.Server.Authenticate` — login UI customisation (logo, skip `DisplayPermissions` by submitting `btnAccept` instead of `btnLogin`).
   - `OAuth2.Server.ValidateLDAP` — credential check via `%SYS.LDAP` (bind anonymously → switch to TLS → bind as admin → look up UserDN by `sAMAccountname` → re-bind with user's password → cleanup).
4. If fronted by a reverse proxy with a different external path (e.g. external `/dev/oauth2`, IRIS-internal `/<csp-app>/oauth2`), add a rewrite rule on the proxy.
5. **Smoke test**: hit `<server>/<csp-app>/oauth2/.well-known/openid-configuration` — must return the OIDC discovery document.

May also need to patch `OAuth2.Server.Client.ValidateRedirectURL` when the redirect URI host is externally constrained.

Worked example: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch11_security/oauth2-server-validate-ldap.cls.xml`.

### Mobile clients (PKCE)

Authorization Code + PKCE — never `client_credentials` or implicit. See `fhir` for the FHIR Façade context.

## SSL/TLS — build the trusted CA chain

To enforce strict server-certificate validation on an IRIS client SSL configuration:

1. Set `Server Certificate Validation = Require` on the SSL config.
2. Build the chain `.PEM` using IRIS-bundled OpenSSL:

   ```bash
   $IRIS_HOME/bin/openssl s_client -servername <hostname> -connect <hostname>:443 -prexit -showcerts
   ```

   **Critical:** `-servername` is required for TLS Server Name Indication (SNI). Without it, `s_client` may return a wildcard / default cert (Kubernetes ingress, shared load balancer) and validation will fail mysteriously against the real cert.

3. The output contains the server cert + intermediate CA. Append the root CA (fetched from the public source — e.g. USERTrust, Let's Encrypt ISRG Root X1) to complete the chain.
4. **Order matters**: server cert → intermediate CA → root CA.
5. **Optimisation**: once the chain works, remove the server's own cert from the `.PEM`. Keep only intermediate + root. The server presents its own cert during the TLS handshake; the IRIS-side file only needs the trust anchors. This decouples the IRIS config from the server's annual cert-renewal cycle.

Helper script: `${CLAUDE_PLUGIN_ROOT}/BestPractices/examples/ch11_security/ssl-trusted-ca-chain.sh`.

## ZAUTHENTICATE for external LDAP

When IRIS must authenticate users against an external LDAP with password-expiry semantics, implement `ZAUTHENTICATE` — a customisable `%SYS` routine. It calls `%SYS.LDAP` to bind and detects the "password expired" response to force a password change.

This is mostly a migration concern (carrying forward an authentication contract from a legacy app). New work prefers OAuth/OIDC.

## Internal account hygiene

### `CSPSystem` needs its own strong password

`CSPSystem` is an internal account used by the Web Gateway. Give it its own strong, unique password — distinct from `_SYSTEM`, `Admin`, `SuperUser`. It is **not** a regular interactive user; password rotation policies for human accounts don't apply, but a long random password is mandatory.

### Initial Security level

For production interop hosts, prefer `Locked Down` when operationally feasible. `Normal` is acceptable only if the network is fully trusted (segmented, no Internet exposure).

`Locked Down` disables more services by default and requires explicit enablement of each used CSP application, REST endpoint, etc. — more setup work, smaller attack surface.

## Reference data — partner-specific SAML attributes

When generating a SAML 2.0 assertion for a partner system, the assertion's `<saml:AttributeStatement>` must include exactly the attribute names the partner's policy declares. Names are case-sensitive and partner-defined; capture the canonical list from the partner's integration spec before coding the assertion generator.

## Reference data — XAdES EPES signature policies

Some e-invoicing and public-sector signature workflows (e.g. Spanish TicketBAI, facturae) require an XAdES EPES signature with a `<xades:SignaturePolicyIdentifier>` block carrying the SHA-1 base64 digest of the policy PDF or URL. The policy reference is partner-provided; the implementation is partner-specific.

## Common pitfalls

- **Using native `%SAML.Assertion` and being surprised by intermittent signature failures** — switch to SAML-COS.
- **Generating the SAML assertion inside SOAP-envelope-aware code** so it inherits envelope namespaces, then watching the standalone-extracted assertion fail validation.
- **Hardcoding the signing cert** instead of aliasing via a per-environment `SAMLCredentials` setting → cert rotation needs a redeploy.
- **OpenSSL `s_client` without `-servername`** → wildcard cert returned, chain build is wrong.
- **Keeping the server cert in the trust chain `.PEM`** → annual cert rotation forces an IRIS config change.
- **Treating `CSPSystem` as a normal account** (deleting it, rotating its password from a human-account script) → Web Gateway breaks.
- **GUID-style AssertionIDs on SAML 1.1** → fixed-format underscore-prefixed IDs required by many partners.
- **Trusting the WSDL's response namespace blindly** — SOAP servers often return a different namespace than the WSDL declares. Capture an actual response and override (see `soap-bo` §"`RESPONSENAMESPACE` doesn't match what the vendor actually returns").

## When NOT to use this skill — fall back to docs

- Application-level role-based authorization inside a CSP/REST app — that's `%SYS.Security.*` / role management, not interop-specific.
- IAM (InterSystems API Manager) / Kong policies — separate product; verify operational specifics against current InterSystems docs.
- Encrypting databases (instance keys, secondary databases) — platform concern, not interop.

## See also

- `soap-bo` — generated SOAP client patches, including the suppression of `xsi:type` and the `RESPONSENAMESPACE` override.
- `fhir` — OAuth 2.0 + PKCE for mobile FHIR clients.
- `production-lifecycle` — where credentials live (`Ens.Config.Credentials`), how they migrate between environments, and namespace-level security boundaries.
- `business-services` — HTTP Basic auth in `OnPreWebMethod` for SOAP inbound services.
