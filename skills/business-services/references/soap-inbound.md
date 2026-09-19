# Inbound SOAP Business Service

Exposing a BS as a SOAP web service, and HTTP Basic Auth on it. Read this only when the inbound is SOAP.

## BS that exposes an inbound SOAP service

When you need a Business Service that accepts inbound SOAP requests:

1. New → General → Web Service in Studio (or generate from a WSDL via the SOAP wizard).
2. Change the parent class from the default `%SOAP.WebService` to **`EnsLib.SOAP.Service`** — this is what makes it an Interop entry point.
3. Override the `Adapter` parameter to blank (default would be `EnsLib.SOAP.InboundAdapter`, which is a separate inbound model and prevents direct WS invocation).
4. Implement web methods with `[WebMethod]` and parameters typed to your `MSG.<Name>Req|Rsp` classes.
5. Override `OnProcessInput` and call the BP synchronously or asynchronously as the use case requires.

Worked example: `../assets/soap-business-service.cls`.


## HTTP Basic Auth on an inbound SOAP BS

When authentication must live in IRIS (not at the gateway / reverse proxy) and the inbound is SOAP, do it in `OnPreWebMethod()`:

> **Deny by RAISING A FAULT. A returned `%Status` is discarded and the call proceeds.** Measured over
> HTTP against a live endpoint: `Quit $$$ERROR(...)` from `OnPreWebMethod` returns **HTTP 200 with the
> web method executed**, and so does falling off the end with no `Quit` at all. Only
> `..ReturnFault(..MakeFault(...))` stops it. Both fail-open spellings look like working auth code.
> All **52** `OnPreWebMethod` methods on the platform declare **no return type** — that is the
> dictionary telling you the value is never read. See deliverable §6.19.

```objectscript
Class MyApp.BS.SoapAuthGuard Extends EnsLib.SOAP.Service
{

/// Blank for direct inbound through the CSP web application.
Parameter ADAPTER;

Parameter NAMESPACE = "http://example.org/authguard";

Parameter SERVICENAME = "AuthGuard";

Parameter CREDENTIALSET As STRING = "MySoapInbound";

/// NO return type, matching every platform implementation.
Method OnPreWebMethod()
{
    Set tAuth = $Get(%request.CgiEnvs("HTTP_AUTHORIZATION"))
    If $ZConvert($Extract(tAuth, 1, 6), "L") '= "basic " {
        Do ..ReturnFault(..MakeFault($$$FAULTServer, "credentials required"))
    }
    Set tDecoded = $System.Encryption.Base64Decode($Extract(tAuth, 7, *))
    If '..CredentialsAccepted($Piece(tDecoded, ":", 1), $Piece(tDecoded, ":", 2, *)) {
        // Same wording deliberately: distinguishable messages are a user-enumeration oracle.
        Do ..ReturnFault(..MakeFault($$$FAULTServer, "credentials required"))
    }
}

Method CredentialsAccepted(pUsername As %String, pPassword As %String) As %Boolean
{
    Set tCred = ##class(Ens.Config.Credentials).%OpenId(..#CREDENTIALSET, 0)
    Quit:'$IsObject(tCred) 0
    Quit:(tCred.Password="") 0
    Quit (tCred.Username = pUsername) && (tCred.Password = pPassword)
}

Method Ping() As %String [ WebMethod ]
{
    Quit "pong"
}

}
```

**It does NOT require `EnsLib.SOAP.InboundAdapter`.** `OnPreWebMethod` is a `%SOAP.WebService` callback, and `EnsLib.SOAP.Service` inherits it from there — measured with the adapter blanked, as above. Three preconditions that are easy to miss, all measured:

- **A production must be running**, or the callback never executes and the endpoint answers `<Ens>ErrProductionNotRunning` as a generic `Server Application Error`. A stopped production refuses everything, which is easily mistaken for this guard working.
- **The production item must be named after the CLASS**, not `<Tipo>.<Name>` — the only place in interop where that is true. Otherwise: `<Ens>ErrBusinessDispatchNameNotRegistered`.
- **The web application must not itself require authentication.** With `AutheEnabled = 32`, HTTP Basic authenticates a WSDL *GET* but a SOAP *POST* is refused by the SOAP layer before this method runs, with `wsse:FailedAuthentication`.

For non-SOAP REST inbound, use the CSP web app's `AutheEnabled` bitmask (see §CSP/Web-app permissions below) and let the gateway handle Basic — OnPreWebMethod is specific to SOAP service classes.

