/// Rule: BestPractices_Interop_IRIS.md §6.19 "HTTP Basic on an inbound SOAP service: `OnPreWebMethod` denies by raising a fault, never by returning a status"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, and the denial measured over real HTTP.
/// Severity: CRITICAL (the natural spelling of this guard fails OPEN — it authenticates nothing and looks correct).
///
/// Pattern: authentication inside the inbound SOAP service, for when it must live in IRIS rather than
/// at the gateway. Direct mode, so `Parameter ADAPTER;` is blank — see §6.17.
///
/// THE ONE THING TO TAKE FROM THIS FILE. A guard that ends
///
///     Method OnPreWebMethod() As %Status { ... Quit $$$ERROR($$$GeneralError, "denied") }
///
/// **does not deny anything.** Measured over HTTP against a live endpoint: the returned status is
/// discarded and the web method runs. Five variants of the same guard, one SOAP POST each, counters
/// incremented inside `OnPreWebMethod` and inside the web method body:
///
///     OnPreWebMethod body                     HTTP  pre  body   response
///     As %Status, Quit $$$OK                   200    1     1   the web method ran
///     As %Status, Quit $$$ERROR(...)           200    1     1   the web method ran ANYWAY
///     As %Status, no Quit at all               200    1     1   the web method ran ANYWAY
///     no return type, Do ..ReturnFault(...)    500    1     0   DENIED, faultstring "denied"
///     no return type, Throw ...                500    1     0   denied, but "Server Application Error"
///
/// So there are two fail-open spellings and one right answer. `..ReturnFault(..MakeFault(...))` is the
/// one to use: `Throw` also stops the call but replaces your message with a generic one, which costs
/// the caller the reason and costs you the support ticket.
///
/// THE DICTIONARY SAID SO FIRST, and this is the reusable lesson. **All 51 `OnPreWebMethod` methods on
/// the platform declare NO return type** — `%SOAP.WebService`, `EnsLib.SOAP.Service`, and 49 others.
/// A callback whose every platform implementation declares no return type is telling you its return
/// value is not read. Declaring `As %Status` on an override does not create a contract; it only makes
/// the returned value look consulted.
///
/// NO ADAPTER IS INVOLVED. `OnPreWebMethod` is a `%SOAP.WebService` callback, and
/// `EnsLib.SOAP.Service Extends Ens.Helper.Service.SyncResponseHandler.HTTP, Ens.BusinessService,
/// %SOAP.WebService` inherits it from there. Measured: this class blanks its adapter and the callback
/// still fires. No adapter class provides it.
///
/// WHAT THE WEB APPLICATION DECIDES, and it is the precondition nobody states. On a web application
/// with `AutheEnabled = 32` (password), HTTP Basic authenticates a **WSDL GET** — but the same
/// credentials on a **SOAP POST** are refused by the SOAP layer before this method runs, with
/// `wsse:FailedAuthentication "The security token could not be authenticated or authorized"` and
/// `pre=0`. Measured, on one app, one credential pair:
///
///     credential carrier              HTTP  reached OnPreWebMethod?  HTTP_AUTHORIZATION
///     Authorization: Basic            500    no                      never read
///     WS-Security UsernameToken       200    yes                     ABSENT
///     both together                   200    yes                     PRESENT
///     neither                         500    no                      never read
///
/// Read the third row carefully. `%request.CgiEnvs("HTTP_AUTHORIZATION")` **is** readable here — but on
/// a password-protected application the request only gets this far if it already authenticated some
/// other way, which makes "authenticate in `OnPreWebMethod`" circular. This guard therefore belongs on
/// an application that does NOT require authentication, so that IRIS lets the request through and this
/// method is the thing deciding.
///
/// THE ITEM NAME MUST BE THE CLASS NAME, which is the opposite of the rule everywhere else. A
/// direct-mode SOAP service is reached through its class, and the CSP dispatcher resolves the config
/// item from that -- so an item named `BS.SoapAuthGuard` for class `Example.BS.SoapAuthGuard` leaves
/// the endpoint answering, with the production **running**:
///
///     <Ens>ErrBusinessDispatchNameNotRegistered: Business dispatch name
///     'Example.BS.SoapAuthGuard' is not registered to run
///
/// Renaming the item to `Example.BS.SoapAuthGuard` turned the same request into HTTP 200. Note the
/// asymmetry inside this one class: the item that HOSTS this service is named by its class, while
/// `TARGETBO` below, which this service SENDS to, is an ordinary `<Tipo>.<Name>` item name.
///
/// AND IT DOES NOT RUN AT ALL WITHOUT A RUNNING PRODUCTION. Measured: with the production stopped, a
/// correctly credentialed POST returns `Server Application Error` whose detail reads
/// `<Ens>ErrProductionNotRunning: No production is running`, and the counter inside `OnPreWebMethod`
/// stays at 0. A stopped production refuses everything, in a way easily mistaken for this guard
/// working. See `production-soap-authguard.cls`.
///
/// NOT VERIFIED, deliberately stated as such: the unauthenticated configuration (`AutheEnabled = 64`)
/// could not be exercised on the measuring instance, because its `UnknownUser` holds **no roles**
/// (`roles=<>`) and so cannot enter the namespace — every request returned a generic
/// `SOAP-ENV:Server Internal Server Error` with `pre=0`. That is a property of that instance, not of
/// IRIS. Before deploying this pattern, confirm on your own instance that an anonymous request reaches
/// the method, and grant `UnknownUser` only the namespace access it needs.
Class Example.BS.SoapAuthGuard Extends EnsLib.SOAP.Service
{

/// CRITICAL: must be BLANK for direct inbound through the CSP web application (§6.17). The guard fires
/// either way -- it comes from %SOAP.WebService, not from an adapter.
Parameter ADAPTER;

Parameter NAMESPACE = "http://example.org/interop/authguard";

Parameter SERVICENAME = "ExampleAuthGuard";

/// Name of the `Ens.Config.Credentials` set holding the expected credentials. A production credential
/// set, not a hard-coded pair, so rotating the password is a configuration change and not a recompile.
Parameter CREDENTIALSET As STRING = "ExampleSoapInbound";

/// Production ITEM name of the target -- items are `<Tipo>.<Name>`, not class names.
Parameter TARGETBO As STRING = "BO.Sink";

/// NO RETURN TYPE -- matching all 51 platform implementations, and matching the fact that the value
/// would be discarded. Deny by raising a fault; there is no other way to stop the call from here.
Method OnPreWebMethod()
{
    Set tAuth = $Get(%request.CgiEnvs("HTTP_AUTHORIZATION"))
    If $ZConvert($Extract(tAuth, 1, 6), "L") '= "basic " {
        // No `Quit` needed and none would help: ReturnFault does not return to this method.
        Do ..ReturnFault(..MakeFault($$$FAULTServer, "credentials required"))
    }
    Set tDecoded = $System.Encryption.Base64Decode($Extract(tAuth, 7, *))
    // The password may itself contain ":" -- take everything after the FIRST one.
    If '..CredentialsAccepted($Piece(tDecoded, ":", 1), $Piece(tDecoded, ":", 2, *)) {
        // Deliberately the same wording as the missing-credentials fault: a caller who can tell
        // "no such user" from "wrong password" has been handed a user-enumeration oracle.
        Do ..ReturnFault(..MakeFault($$$FAULTServer, "credentials required"))
    }
}

/// Compare against the production's credential set. Override to reach a different store.
Method CredentialsAccepted(pUsername As %String, pPassword As %String) As %Boolean
{
    Set tCred = ##class(Ens.Config.Credentials).%OpenId(..#CREDENTIALSET, 0)
    Quit:'$IsObject(tCred) 0
    // A missing or empty stored password must never match an empty supplied one.
    // PARENTHESISED deliberately: a postconditional expression ends at the FIRST space, so
    // `Quit:tCred.Password = "" 0` does not compile -- #1054 Invalid expression : '='.
    Quit:(tCred.Password="") 0
    Quit (tCred.Username = pUsername) && (tCred.Password = pPassword)
}

/// Liveness method. Reaching it at all is the observable proof that the guard allowed the call.
Method Ping() As %String [ WebMethod ]
{
    Quit "pong"
}

/// The real inbound contract, dispatching to the production.
Method SubmitOrder(pOrderId As %String) As %String [ WebMethod ]
{
    #Dim tRequest As Ens.StringContainer = ##class(Ens.StringContainer).%New(pOrderId)
    #Dim tResponse As Ens.Response
    Set tSC = ..SendRequestSync(..#TARGETBO, tRequest, .tResponse)
    // Map the %Status to a fault: HERE a returned status IS consulted, because a WebMethod's return
    // value is the SOAP body. That is exactly the asymmetry that makes the OnPreWebMethod trap so easy.
    $$$ThrowOnError(tSC)
    Quit "accepted"
}

}
