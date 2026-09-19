/// Rule: BestPractices_Interop_IRIS.md §6.19 "HTTP Basic on an inbound SOAP service: `OnPreWebMethod` denies by raising a fault, never by returning a status"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN, over real HTTP.
/// Severity: CRITICAL (the guard it protects fails OPEN when written the natural way).
///
/// Pattern: the oracle for `soap-inbound-onprewebmethod-auth.cls`. It posts real SOAP envelopes to a
/// real endpoint, because the claim under test — "the call is denied" — is not visible from inside the
/// process. A test that called `OnPreWebMethod` directly and inspected its return value would pass
/// against the fail-open spelling, which is the exact defect.
///
/// THE POSITIVE CONTROL COMES FIRST, and the rest of the suite is worthless without it. Two of the
/// three HTTP assertions are about a request being REFUSED, and a refusal is indistinguishable from a
/// broken endpoint, a missing web application or a wrong SOAPAction. So `TestCorrectCredentialsReach`
/// must see `pong` come back over the wire before any denial means anything.
///
/// SETUP AND TEARDOWN ARE REAL CONFIGURATION. The suite creates a throwaway CSP application and an
/// `Ens.Config.Credentials` set, and removes both afterwards. If either cannot be created the suite
/// FAILS -- it does not skip. A skipped auth test reads exactly like a passing one.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=360  8 methods, 0 failed
///     missing-credentials branch returns a status run=361  2 failed -- MissingHeaderIsDenied,
///                                                          TheSampleDeniesByFaultingNotByReturning
///     wrong-password branch returns a status      run=362  4 failed -- WrongPasswordIsDenied,
///                                                          DenialDoesNotEnumerateUsers,
///                                                          EmptyStoredPasswordCannotMatch, TheSample...
///     CredentialsAccepted always returns 1        run=363  2 failed -- WrongPasswordIsDenied,
///                                                          DenialDoesNotEnumerateUsers
///     the empty-stored-password guard removed     run=364  1 failed -- EmptyStoredPasswordCannotMatch
///     reverted                                    run=365  8 methods, 0 failed
///
/// Mutation 1 is the demonstration, not just a check: swapping `Do ..ReturnFault(...)` for
/// `Quit $$$ERROR(...)` in the missing-credentials branch makes an **uncredentialed** request succeed.
/// That is the whole finding, reproduced on demand.
///
/// FOUR OF ITS OWN DEFECTS, kept here because each one produced a false result first:
///   * `..Port` stashed in `OnBeforeAllTests` read back EMPTY in the test methods, so every call went
///     to localhost:80 and failed with `#6059`. Seven failures, none of them about authentication.
///   * `ReturnType = ''` matched none of the 52 platform methods -- the dictionary stores an undeclared
///     return type as NULL, so the count came back "52 typed" and inverted the assertion.
///   * `%Get("Implementation")` on a stream column returns an id, not a stream, so the text searched was
///     "" and both content assertions would have passed vacuously.
///   * `Base64Encode()` without its second argument inserts line breaks, and a CRLF in a header value
///     corrupted the request.
/// In all four the suite REPORTED A REFUSAL. Only the positive control distinguished "denied" from
/// "never arrived" -- and at one point `MissingHeaderIsDenied` and `DenialDoesNotEnumerateUsers` were
/// passing green while every single request was failing with `Server Application Error`.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SoapOnPreWebMethodDeny", namespace="<NS>")
Class Example.Tests.SoapOnPreWebMethodDeny Extends %UnitTest.TestProduction
{

/// Without this running, every POST returns a generic `Server Application Error` and `OnPreWebMethod`
/// never executes -- see `production-soap-authguard.cls`.
Parameter PRODUCTION = "Example.Productions.SoapAuthGuardFixture";

/// Throwaway CSP application, created and deleted by this suite.
Parameter APP As STRING = "/example-soap-authguard-test";

/// The credential set the sample reads. Must match the sample's CREDENTIALSET parameter.
Parameter CREDSET As STRING = "ExampleSoapInbound";

Parameter BASICUSER As STRING = "orderfeed";

/// Not a secret: a value this suite writes and then deletes, existing only to be compared.
Parameter BASICPWD As STRING = "guard-fixture-value";

/// The web application requires authentication, so the SOAP layer demands a WS-Security UsernameToken
/// before it will dispatch at all (§6.19). These are the IRIS INSTALL DEFAULTS, not credentials of any
/// deployment -- override them if your measuring instance differs.
Parameter WSUSER As STRING = "_SYSTEM";

Parameter WSPWD As STRING = "SYS";

/// NOT an instance Property. Measured: a value stashed on `..Something` in `OnBeforeAllTests` reads
/// back EMPTY inside the test methods, and an empty port sent %Net.HttpRequest to localhost:80 --
/// every assertion then failed with `#6059 Unable to open TCP/IP socket`, which looks exactly like a
/// denial. Read it fresh, per call, from the one place that has it.
ClassMethod WebServerPort() As %Integer [ Private ]
{
    New $Namespace
    Set $Namespace = "%SYS"
    Quit $Get(^%SYS("WebServer", "Port"))
}

/// A no-op override. The inherited TestControl() would start the production, hang and stop it again,
/// leaving nothing running for the tests that follow.
Method TestControl() As %Status
{
    Quit $$$OK
}

Method OnBeforeAllTests() As %Status
{
    // Capture the interop namespace BEFORE hopping: inside %SYS, $Namespace is "%SYS", so reading it
    // there would create the web application against the wrong namespace and every POST would 404.
    Set tNs = $Namespace
    New $Namespace
    Set $Namespace = "%SYS"
    If ##class(Security.Applications).Exists(..#APP) {
        Do ##class(Security.Applications).Delete(..#APP)
    }
    Set tProps("NameSpace") = tNs
    Set tProps("Enabled") = 1
    // 32 = AuthePassword. See §CSP/Web-app permissions for the bitmask.
    Set tProps("AutheEnabled") = 32
    Set tProps("Description") = "throwaway -- Example.Tests.SoapOnPreWebMethodDeny"
    Set tSC = ##class(Security.Applications).Create(..#APP, .tProps)
    If $$$ISERR(tSC) Quit tSC
    Set $Namespace = tNs
    Set tSC = ..WriteCredential(..#BASICPWD)
    If $$$ISERR(tSC) Quit tSC
    // The guard is unreachable without this, and an unreachable guard refuses everything.
    Set tSC = ##class(Ens.Director).StartProduction(..#PRODUCTION)
    If $$$ISERR(tSC) Quit tSC
    For i = 1:1:40 {
        If ##class(Ens.Director).IsProductionRunning() { Quit }
        Hang 0.25
    }
    If '##class(Ens.Director).IsProductionRunning() {
        Quit $$$ERROR($$$GeneralError, "production " _ ..#PRODUCTION _ " did not come up")
    }
    Quit $$$OK
}

/// Write the credential set the sample reads. `Ens.Config.Credentials` is an ordinary %Persistent class
/// whose IdKey is **SystemName** -- there is no `SetCredential()` helper to call. (`RemoveCredential()`
/// does not exist either: invoking it raises <METHOD DOES NOT EXIST> at runtime.)
ClassMethod WriteCredential(pPassword As %String) As %Status [ Private ]
{
    If ##class(Ens.Config.Credentials).%ExistsId(..#CREDSET) {
        Set tSC = ##class(Ens.Config.Credentials).%DeleteId(..#CREDSET)
        If $$$ISERR(tSC) Quit tSC
    }
    Set tCred = ##class(Ens.Config.Credentials).%New()
    Set tCred.SystemName = ..#CREDSET
    Set tCred.Username = ..#BASICUSER
    Set tCred.Password = pPassword
    Quit tCred.%Save()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Ens.Director).StopProduction(15, 1)
    If ##class(Ens.Config.Credentials).%ExistsId(..#CREDSET) {
        Do ##class(Ens.Config.Credentials).%DeleteId(..#CREDSET)
    }
    New $Namespace
    Set $Namespace = "%SYS"
    If ##class(Security.Applications).Exists(..#APP) {
        Do ##class(Security.Applications).Delete(..#APP)
    }
    Quit $$$OK
}

/// The faultstring alone, for assertion messages -- a raw envelope prefix diagnoses nothing.
ClassMethod Fault(pBody As %String) As %String [ Private ]
{
    Quit $Select(pBody [ "<faultstring>":$Piece($Piece(pBody, "<faultstring>", 2), "</faultstring>", 1), 1:"<no faultstring> " _ $Extract(pBody, 1, 120))
}

/// One SOAP POST. pBasic: "" sends no Authorization header at all.
/// Returns the HTTP status; pBody is the response text.
Method Post(pMethod As %String, pBasic As %String, Output pBody As %String) As %Integer [ Private ]
{
    Set pBody = ""
    Set tWsse = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
    Set tType = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText"
    Set tEnv = "<?xml version=""1.0"" encoding=""UTF-8""?>"
        _ "<S:Envelope xmlns:S=""http://schemas.xmlsoap.org/soap/envelope/"">"
        _ "<S:Header><wsse:Security xmlns:wsse=""" _ tWsse _ """><wsse:UsernameToken>"
        _ "<wsse:Username>" _ ..#WSUSER _ "</wsse:Username>"
        _ "<wsse:Password Type=""" _ tType _ """>" _ ..#WSPWD _ "</wsse:Password>"
        _ "</wsse:UsernameToken></wsse:Security></S:Header>"
        _ "<S:Body><" _ pMethod _ " xmlns=""http://example.org/interop/authguard""/></S:Body>"
        _ "</S:Envelope>"
    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = "localhost"
    Set tPort = ..WebServerPort()
    If tPort = "" {
        Set pBody = "NO WEB SERVER PORT -- refusing to call, a failure here would look like a denial"
        Quit -2
    }
    Set tReq.Port = tPort
    Set tReq.Timeout = 30
    Set tReq.ContentType = "text/xml"
    Do tReq.SetHeader("SOAPAction", "http://example.org/interop/authguard/Example.BS.SoapAuthGuard." _ pMethod)
    If pBasic '= "" {
        // The SECOND ARGUMENT MATTERS: Base64Encode() inserts line breaks by default, and a CRLF
        // inside an HTTP header value corrupts the request. Pass 1 to suppress them.
        Do tReq.SetHeader("Authorization", "Basic " _ $System.Encryption.Base64Encode(pBasic, 1))
    }
    Do tReq.EntityBody.Write(tEnv)
    Set tSC = tReq.Post(..#APP _ "/Example.BS.SoapAuthGuard.cls")
    // A transport failure is NOT a denial. Report it as itself.
    If $$$ISERR(tSC) {
        Set pBody = "TRANSPORT FAILURE: " _ $System.Status.GetErrorText(tSC)
        Quit -1
    }
    Set tStatus = tReq.HttpResponse.StatusCode
    If $IsObject(tReq.HttpResponse.Data) {
        While 'tReq.HttpResponse.Data.AtEnd { Set pBody = pBody _ tReq.HttpResponse.Data.Read(16000) }
    }
    Quit tStatus
}

/// POSITIVE CONTROL -- must run first and must pass, or every refusal below is unexplained.
Method TestCorrectCredentialsReachTheWebMethod() As %Status
{
    Set tCode = ..Post("Ping", ..#BASICUSER _ ":" _ ..#BASICPWD, .tBody)
    Do $$$AssertEquals(tCode, 200, "POSITIVE CONTROL: a correctly credentialed SOAP POST reaches the web method (HTTP " _ tCode _ "): " _ ..Fault(tBody))
    Do $$$AssertTrue(tBody [ "pong", "and the web method's own return value comes back, so the guard allowed the call through")
    Quit $$$OK
}

/// The central claim: a wrong password stops the call. `pre` ran, the body did not.
Method TestWrongPasswordIsDenied() As %Status
{
    Set tCode = ..Post("Ping", ..#BASICUSER _ ":definitely-not-the-password", .tBody)
    Do $$$AssertEquals(tCode, 500, "a wrong password is refused with a SOAP fault, not a 200 (HTTP " _ tCode _ ")")
    Do $$$AssertTrue(tBody [ "credentials required", "and the fault carries the guard's own message, got: " _ ..Fault(tBody))
    // The whole point: the web method must NOT have produced a body.
    Do $$$AssertNotTrue(tBody [ "pong", "and the web method did NOT run -- this is the assertion the fail-open spelling breaks")
    Quit $$$OK
}

/// No Authorization header at all.
Method TestMissingHeaderIsDenied() As %Status
{
    Set tCode = ..Post("Ping", "", .tBody)
    Do $$$AssertEquals(tCode, 500, "a request with no Authorization header is refused (HTTP " _ tCode _ ")")
    Do $$$AssertNotTrue(tBody [ "pong", "and the web method did not run")
    Quit $$$OK
}

/// A wrong password and an unknown user must be indistinguishable to the caller, or the endpoint is a
/// user-enumeration oracle.
Method TestDenialDoesNotEnumerateUsers() As %Status
{
    Set tUnknown = ..Post("Ping", "no-such-user:whatever", .tBodyUnknown)
    Set tWrong = ..Post("Ping", ..#BASICUSER _ ":wrong", .tBodyWrong)
    Do $$$AssertEquals(tUnknown, tWrong, "an unknown user and a wrong password return the same HTTP status")
    Set tFaultU = $Piece($Piece(tBodyUnknown, "<faultstring>", 2), "</faultstring>", 1)
    Set tFaultW = $Piece($Piece(tBodyWrong, "<faultstring>", 2), "</faultstring>", 1)
    Do $$$AssertNotEquals(tFaultU, "", "POSITIVE CONTROL: a faultstring was actually parsed out, so comparing two of them means something")
    Do $$$AssertEquals(tFaultU, tFaultW, "and both carry the same faultstring: <" _ tFaultU _ "> vs <" _ tFaultW _ ">")
    Quit $$$OK
}

/// An empty stored password must not be matched by an empty supplied one.
Method TestEmptyStoredPasswordCannotMatch() As %Status
{
    Do ..WriteCredential("")
    Set tCode = ..Post("Ping", ..#BASICUSER _ ":", .tBody)
    // restore before asserting, so a failure cannot leave the fixture broken for the next method
    Do ..WriteCredential(..#BASICPWD)
    Do $$$AssertEquals(tCode, 500, "an empty stored password is not matched by an empty supplied one (HTTP " _ tCode _ ")")
    Do $$$AssertNotTrue(tBody [ "pong", "and the web method did not run")
    Quit $$$OK
}

/// THE DICTIONARY FACT that predicts the whole trap, asserted so it cannot drift: no platform
/// `OnPreWebMethod` declares a return type, so a returned status is not part of the contract.
Method TestNoPlatformOnPreWebMethodDeclaresAReturnType() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT COUNT(*) AS total, "
        _ "SUM(CASE WHEN ReturnType IS NULL OR ReturnType = '' THEN 0 ELSE 1 END) AS typed "
        _ "FROM %Dictionary.CompiledMethod WHERE Name = 'OnPreWebMethod'")
    Do $$$AssertTrue(tRs.%SQLCODE >= 0, "the dictionary query ran: SQLCODE " _ tRs.%SQLCODE)
    Do tRs.%Next()
    // POSITIVE CONTROL: a zero `typed` means nothing if `total` is also zero.
    Do $$$AssertTrue(tRs.%Get("total") > 40, "POSITIVE CONTROL: the platform really does carry many OnPreWebMethod overrides, found " _ tRs.%Get("total"))
    // `IS NULL OR = ` deliberately: the dictionary stores an undeclared return type as NULL, and
    // `ReturnType = ` alone matched none of them, so the count came back 52-of-52 "typed".
    Do $$$AssertEquals(+tRs.%Get("typed"), 0, "and NOT ONE of them declares a return type -- found " _ +tRs.%Get("typed"))
    Quit $$$OK
}

/// The sample must not regress into either fail-open spelling. Read from the dictionary, not the file,
/// so it tests what IRIS compiled.
Method TestTheSampleDeniesByFaultingNotByReturning() As %Status
{
    // %OpenId, not a SELECT: `%Get("Implementation")` on a stream column returns an id string, not a
    // stream, so reading it that way yields "" and the search below would vacuously pass.
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("Example.BS.SoapAuthGuard||OnPreWebMethod", 0)
    Do $$$AssertTrue($IsObject(tDef), "POSITIVE CONTROL: the sample's OnPreWebMethod is in the dictionary at all")
    Do $$$AssertEquals(tDef.ReturnType, "", "the sample's OnPreWebMethod declares NO return type, like all 52 platform ones")
    Set tImpl = ""
    If $IsObject(tDef.Implementation) {
        Do tDef.Implementation.Rewind()
        While 'tDef.Implementation.AtEnd { Set tImpl = tImpl _ tDef.Implementation.Read(8000) }
    }
    Do $$$AssertTrue($Length(tImpl) > 0, "POSITIVE CONTROL: the implementation text was actually read, so searching it means something")
    Do $$$AssertTrue(tImpl [ "ReturnFault", "it denies via ReturnFault")
    Do $$$AssertNotTrue(tImpl [ "$$$ERROR", "and it does NOT return a status, which would fail open")
    Quit $$$OK
}

}
