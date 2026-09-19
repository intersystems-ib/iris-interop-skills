/// Rule: BestPractices_Interop_IRIS.md §11.14 "PKCE: IRIS gives you one private method, and the half that protects you is the server's"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and RUN, digests cross-checked against an independent implementation.
/// Severity: CRITICAL (a client that sends a malformed challenge, or a server that never checks it, both look like working PKCE).
///
/// Pattern: the client half of Authorization Code + PKCE, which is all your IRIS code controls.
/// `skills/security` says "Authorization Code + PKCE — never `client_credentials` or implicit" and stops
/// there. These are the parts that sentence leaves out.
///
/// IRIS'S ONLY PKCE METHOD IS PRIVATE. `%SYS.OAuth2.Authorization` carries 16 methods; exactly one is
/// named for PKCE and it is **`MakeCodeVerifier()`, declared Private**. Measured: calling it from outside
/// raises `<PRIVATE METHOD>`. No other method on that class takes a challenge or a verifier -- not in a
/// name, not in a formal spec. So you generate the verifier yourself, and you compute the challenge
/// yourself.
///
/// THE CHALLENGE IS base64url WITHOUT PADDING, and plain Base64 is wrong in three ways at once. Measured
/// on this instance:
///
///     $System.Encryption.Base64Encode(sha, 1)   yXDQdtg4ee/M85tLOnFTjlJIFGMNoljyjRqcnoRUBc0=
///                                               44 chars, contains '/', contains '=' padding
///     after +/ -> -_ and stripping '='          yXDQdtg4ee_M85tLOnFTjlJIFGMNoljyjRqcnoRUBc0
///                                               43 chars, unreserved only
///
/// `+`, `/` and `=` are all illegal in a `code_challenge`. A client that sends the padded form is either
/// rejected or -- worse, against a lenient server -- produces a mismatch that appears intermittently.
///
/// THE HASH ARGUMENT ORDER IS LOAD-BEARING. `$System.Encryption.SHAHash(256, pText)` is correct;
/// `SHAHash(pText, 256)` raises `<ILLEGAL VALUE>`. Verified against a known digest before anything was
/// built on it: `Base64Encode(SHAHash(256, "abc"), 1)` is
/// `ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=`, byte-identical to an independent SHA-256.
///
/// WHERE THE PARAMETERS GO. There is no PKCE argument, but there is a channel:
///
///     GetAuthorizationCodeEndpoint(applicationName, scope, redirectURL, &properties,
///                                 *isAuthorized, *sc, responseMode, sessionId)
///     MakeAuthorizationCodeURL(client, token, redirect, &properties, *sc)
///
/// The `&properties` array is where `code_challenge` and `code_challenge_method` belong.
///
/// AND THE HALF YOU CANNOT WRITE. **A server that never verifies the challenge still issues a token.**
/// Every line in this file will run, the flow will complete, a token will come back, and the protection
/// will be entirely absent -- because PKCE is a proof the *server* checks. Confirm on your authorization
/// server that the challenge is required and verified; a client-side PKCE implementation on its own buys
/// nothing.
///
/// NOT MEASURED HERE, and stated as such: there is no OAuth2 server to test that against on this
/// instance. `OAuth2.Server.Configuration` has **zero rows**, and the configuration classes
/// (`OAuth2.Client`, `OAuth2.Server.Configuration`, `OAuth2.AccessToken`) exist **only in %SYS** -- all
/// three are absent from the interop namespace, while `%SYS.OAuth2.Authorization` is present in both. So
/// `MakeAuthorizationCodeURL`'s `client As OAuth2.Client` parameter names a class your interop namespace
/// cannot see, and that dangling reference compiles anyway (§6.20).
Class Example.UTL.OAuth2Pkce Extends %RegisteredObject
{

/// RFC 7636 allows 43-128 characters. 32 random bytes base64url-encoded is 43 -- the minimum, which is
/// also the length IRIS's own private helper produces.
Parameter RANDOMBYTES As INTEGER = 32;

/// The only method name the spec fixes. "plain" is also legal and is never the right choice.
Parameter METHOD As STRING = "S256";

/// A fresh code verifier. IRIS's `MakeCodeVerifier()` is Private, so this does not call it.
/// Uses the platform CSPRNG: a verifier from a predictable source defeats the whole exchange.
ClassMethod MakeVerifier() As %String
{
    Quit ..Base64Url($System.Encryption.GenCryptRand(..#RANDOMBYTES))
}

/// The S256 challenge for a verifier.
ClassMethod Challenge(pVerifier As %String) As %String
{
    // (256, text) -- NOT (text, 256), which raises <ILLEGAL VALUE>.
    Quit ..Base64Url($System.Encryption.SHAHash(256, pVerifier))
}

/// base64url, unpadded. The three substitutions that make a Base64 string legal in a URL parameter.
ClassMethod Base64Url(pBytes As %String) As %String
{
    // The 1 suppresses line breaks; without it a long value arrives with CRLFs embedded.
    Set tPlain = $System.Encryption.Base64Encode(pBytes, 1)
    // '+' -> '-', '/' -> '_', then drop the '=' padding entirely.
    Quit $Translate($Translate(tPlain, "+/", "-_"), "=")
}

/// Put the challenge on the authorization request. `properties` is the array
/// `GetAuthorizationCodeEndpoint` and `MakeAuthorizationCodeURL` both accept by reference.
/// Returns the verifier, which the CALLER must keep until the token request -- it is the secret.
ClassMethod AddChallenge(ByRef pProperties As %String) As %String
{
    Set tVerifier = ..MakeVerifier()
    Set pProperties("code_challenge") = ..Challenge(tVerifier)
    Set pProperties("code_challenge_method") = ..#METHOD
    Quit tVerifier
}

/// Put the verifier on the token request. Separate method because it happens at a different step, and
/// sending the challenge here (or the verifier on the authorization request) is the natural mix-up.
ClassMethod AddVerifier(ByRef pProperties As %String, pVerifier As %String)
{
    Set pProperties("code_verifier") = pVerifier
}

/// Is this string usable as a verifier? Length and character set, both from the spec.
ClassMethod VerifierIsWellFormed(pVerifier As %String) As %Boolean
{
    Set tLen = $Length(pVerifier)
    // NO SPACES inside a postconditional expression: it ends at the FIRST space, so
    // `Quit:(tLen < 43) || (tLen > 128) 0` is #1054 Invalid expression : '||'.
    Quit:((tLen<43)||(tLen>128)) 0
    // AN EXPLICIT FLAG, not the loop counter. `Quit i = tLen` after this loop is TRUE both when the loop
    // ran to the end and when it broke on the LAST character -- so a verifier whose only illegal
    // character is the final one passes. Measured: `...IWSa/` was accepted until this was rewritten.
    Set tOk = 1
    For i = 1:1:tLen {
        Set tChar = $Extract(pVerifier, i)
        Continue:tChar?1(1A,1N)
        // Parenthesised and space-free, for the same reason as the length check above.
        Continue:("-._~"[tChar)
        Set tOk = 0
        Quit
    }
    Quit tOk
}

}
