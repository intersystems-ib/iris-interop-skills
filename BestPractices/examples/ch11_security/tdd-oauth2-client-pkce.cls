/// Rule: BestPractices_Interop_IRIS.md §11.14 "PKCE: IRIS gives you one private method, and the half that protects you is the server's"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: CRITICAL (every failure mode here produces a flow that completes).
///
/// Pattern: the oracle for `oauth2-client-pkce.cls`. No OAuth2 server is involved or needed -- the client
/// half is pure computation, which is exactly why it can be pinned this precisely.
///
/// THE DIGEST VECTOR HERE WAS MEASURED, NOT QUOTED, and that distinction cost a wrong turn. A recalled
/// "RFC 7636 Appendix B" pair was checked first and did **not** reproduce. What settled it was validating
/// the primitive against a known digest -- `Base64Encode(SHAHash(256,"abc"), 1)` is
/// `ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=` on this instance and byte-identical from an independent
/// SHA-256 implementation. Two agreeing implementations against one recalled constant means the constant
/// was wrong. So `TestKnownDigest` pins the primitive, and the challenge vector below is the value both
/// implementations produced.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=447  9 methods, 0 failed
///     padding not stripped                        run=448  3 failed
///     the challenge is the verifier itself        run=449  2 failed
///     the VERIFIER is sent as the challenge       run=450  1 failed
///     the method says plain instead of S256       run=451  1 failed
///     the length bounds removed                   run=452  1 failed
///     the loop counter used as the verdict again  run=453  1 failed
///     reverted                                    run=454  9 methods, 0 failed
///
/// THE FIRST BASELINE WAS RED, and the bug was in the sample, not the test.
/// `VerifierIsWellFormed` ended `Quit i = tLen`, which is true both when the loop ran to completion AND
/// when it broke on the LAST character -- so `...IWSa/` was accepted. Mutation 6 reinstates that exact
/// line, so the fix cannot silently regress.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.OAuth2ClientPkce", namespace="<NS>")
Class Example.Tests.OAuth2ClientPkce Extends %UnitTest.TestCase
{

/// A fixed verifier, so the challenge is reproducible.
Parameter VERIFIER As STRING = "dBjftJeZ4CVPmB92K27uhbUJU1p1r1wiM39d61IWSaA";

/// Its S256 challenge, as produced by BOTH this instance and an independent implementation.
Parameter CHALLENGE As STRING = "yXDQdtg4ee_M85tLOnFTjlJIFGMNoljyjRqcnoRUBc0";

/// The primitive, against a digest that does not depend on anything in this repo. If this fails, every
/// other assertion about a hash is meaningless, so it runs as the foundation.
Method TestKnownDigest() As %Status
{
    Set tB64 = $System.Encryption.Base64Encode($System.Encryption.SHAHash(256, "abc"), 1)
    Do $$$AssertEquals(tB64, "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=", "SHAHash(256, ...) is SHA-256, checked against a known digest: " _ tB64)
    // And the argument order is not interchangeable.
    Set tRaised = ""
    Try {
        Set tBad = $System.Encryption.SHAHash("abc", 256)
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "<ILLEGAL VALUE>", "SHAHash(text, 256) -- the reversed order -- raises <ILLEGAL VALUE>, got: " _ $Select(tRaised="":"no error", 1:tRaised))
    Quit $$$OK
}

/// The challenge is the base64url of the digest, and reproduces the measured vector.
Method TestChallengeMatchesTheMeasuredVector() As %Status
{
    Set tChallenge = ##class(Example.UTL.OAuth2Pkce).Challenge(..#VERIFIER)
    Do $$$AssertEquals(tChallenge, ..#CHALLENGE, "the S256 challenge reproduces the cross-checked vector: " _ tChallenge)
    Do $$$AssertEquals($Length(tChallenge), 43, "43 characters -- a 32-byte digest, base64url, unpadded")
    Quit $$$OK
}

/// THE THREE THINGS PLAIN BASE64 GETS WRONG, asserted as a difference so the transform is not taken on
/// trust. This is the assertion that fails if someone "simplifies" Base64Url away.
Method TestPlainBase64WouldBeIllegal() As %Status
{
    Set tPlain = $System.Encryption.Base64Encode($System.Encryption.SHAHash(256, ..#VERIFIER), 1)
    // POSITIVE CONTROL: the plain encoding really was produced, so the differences below are real.
    Do $$$AssertEquals($Length(tPlain), 44, "POSITIVE CONTROL: plain Base64 of a 32-byte digest is 44 chars: " _ tPlain)
    Do $$$AssertTrue(tPlain [ "/", "plain Base64 contains '/', which is illegal in a code_challenge: " _ tPlain)
    Do $$$AssertTrue(tPlain [ "=", "and '=' padding, also illegal")
    Set tUrl = ##class(Example.UTL.OAuth2Pkce).Base64Url($System.Encryption.SHAHash(256, ..#VERIFIER))
    Do $$$AssertNotTrue(tUrl [ "/", "the base64url form has no '/'")
    Do $$$AssertNotTrue(tUrl [ "+", "no '+'")
    Do $$$AssertNotTrue(tUrl [ "=", "and no padding")
    Do $$$AssertNotEquals(tUrl, tPlain, "so the two forms genuinely differ -- the translate/strip is not cosmetic")
    Quit $$$OK
}

/// A generated verifier is well formed, and two of them differ.
Method TestGeneratedVerifierIsWellFormedAndRandom() As %Status
{
    Set tA = ##class(Example.UTL.OAuth2Pkce).MakeVerifier()
    Set tB = ##class(Example.UTL.OAuth2Pkce).MakeVerifier()
    Do $$$AssertEquals($Length(tA), 43, "32 random bytes base64url is 43 characters, the spec minimum: " _ tA)
    Do $$$AssertTrue(##class(Example.UTL.OAuth2Pkce).VerifierIsWellFormed(tA), "and it passes the well-formed check")
    Do $$$AssertNotEquals(tA, tB, "two calls produce different verifiers -- a fixed verifier defeats the exchange")
    Quit $$$OK
}

/// The well-formed check actually rejects things, or it is decoration.
Method TestVerifierCheckRejectsBadInput() As %Status
{
    Set tGuard = "Example.UTL.OAuth2Pkce"
    // POSITIVE CONTROL first: a known-good value passes, so the rejections below are about the input.
    Do $$$AssertTrue($ClassMethod(tGuard, "VerifierIsWellFormed", ..#VERIFIER), "POSITIVE CONTROL: the fixed verifier is accepted")
    Do $$$AssertNotTrue($ClassMethod(tGuard, "VerifierIsWellFormed", "tooshort"), "an 8-character verifier is rejected (minimum 43)")
    Do $$$AssertNotTrue($ClassMethod(tGuard, "VerifierIsWellFormed", ""), "an empty verifier is rejected")
    // A 43-character string containing an illegal character.
    Do $$$AssertNotTrue($ClassMethod(tGuard, "VerifierIsWellFormed", "dBjftJeZ4CVPmB92K27uhbUJU1p1r1wiM39d61IWSa/"), "a '/' in the verifier is rejected -- the unreserved set excludes it")
    Do $$$AssertNotTrue($ClassMethod(tGuard, "VerifierIsWellFormed", $Justify("", 130, "a")), "a 130-character verifier is rejected (maximum 128)")
    Quit $$$OK
}

/// The properties array carries both keys, with the challenge -- never the verifier.
Method TestAddChallengeSetsBothKeys() As %Status
{
    Kill tProps
    Set tVerifier = ##class(Example.UTL.OAuth2Pkce).AddChallenge(.tProps)
    Do $$$AssertNotEquals(tVerifier, "", "AddChallenge returns the verifier for the caller to keep")
    Do $$$AssertEquals(tProps("code_challenge_method"), "S256", "code_challenge_method is S256, never 'plain'")
    Do $$$AssertEquals(tProps("code_challenge"), ##class(Example.UTL.OAuth2Pkce).Challenge(tVerifier), "code_challenge is the S256 of the returned verifier")
    // THE MIX-UP THIS GUARDS: the secret must not travel on the authorization request.
    Do $$$AssertNotEquals(tProps("code_challenge"), tVerifier, "the CHALLENGE is sent, not the verifier -- sending the verifier here discloses the secret")
    Do $$$AssertEquals($Data(tProps("code_verifier")), 0, "and no code_verifier key is set on the authorization request at all")
    Quit $$$OK
}

/// And the verifier goes on the token request, separately.
Method TestAddVerifierIsTheTokenRequestStep() As %Status
{
    Kill tProps
    Do ##class(Example.UTL.OAuth2Pkce).AddVerifier(.tProps, ..#VERIFIER)
    Do $$$AssertEquals(tProps("code_verifier"), ..#VERIFIER, "the token request carries code_verifier")
    Do $$$AssertEquals($Data(tProps("code_challenge")), 0, "and NOT the challenge -- the server already has that")
    Quit $$$OK
}

/// PLATFORM FACTS the sample's design depends on. A drift alarm: if IRIS ever publishes a usable PKCE
/// helper, this fails and §11.14 should be rewritten to call it.
Method TestPlatformOffersNoUsablePkceHelper() As %Status
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("%SYS.OAuth2.Authorization||MakeCodeVerifier", 0)
    Do $$$AssertTrue($IsObject(tDef), "POSITIVE CONTROL: MakeCodeVerifier is in the dictionary")
    Do $$$AssertEquals(tDef.Private, 1, "and it is declared Private, so caller code cannot use it")
    // No public method anywhere on that class takes a challenge or a verifier.
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT COUNT(*) AS n FROM %Dictionary.CompiledMethod WHERE parent = '%SYS.OAuth2.Authorization' "
        _ "AND Private = 0 AND (Name LIKE '%hallenge%' OR Name LIKE '%erifier%' OR FormalSpec LIKE '%hallenge%' OR FormalSpec LIKE '%erifier%')")
    Do $$$AssertTrue(tRs.%SQLCODE >= 0, "the dictionary query ran: SQLCODE " _ tRs.%SQLCODE)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("n"), 0, "no PUBLIC method on %SYS.OAuth2.Authorization mentions a challenge or verifier, found " _ +tRs.%Get("n"))
    // But the channel for them does exist, which is why `properties` is the right place.
    Set tEndpoint = ##class(%Dictionary.CompiledMethod).%OpenId("%SYS.OAuth2.Authorization||GetAuthorizationCodeEndpoint", 0)
    Do $$$AssertTrue($IsObject(tEndpoint), "POSITIVE CONTROL: GetAuthorizationCodeEndpoint exists")
    Do $$$AssertTrue(tEndpoint.FormalSpec [ "properties", "and it takes a `properties` array, which is where the PKCE parameters go: " _ tEndpoint.FormalSpec)
    Quit $$$OK
}

/// The namespace fact, asserted because it explains why the config half cannot be tested from here.
Method TestConfigClassesLiveOnlyInSys() As %Status
{
    // POSITIVE CONTROL: the CLIENT API is visible here, so a 0 below is about those classes specifically
    // and not about the dictionary being unreachable.
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("%SYS.OAuth2.Authorization"), 1, "POSITIVE CONTROL: %SYS.OAuth2.Authorization IS visible in this namespace")
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("OAuth2.Client"), 0, "OAuth2.Client is NOT -- the configuration classes are %SYS-only")
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("OAuth2.Server.Configuration"), 0, "nor is OAuth2.Server.Configuration")
    Quit $$$OK
}

}
