/// Rule: BestPractices_Interop_IRIS.md §11.3 "SAML 2.0 — attaching a custom security header to a generated SOAP BO"
/// Validity: Still valid.
/// Severity: High.
///
/// Pattern: The wizard-generated SOAP BO doesn't expose hooks for a wsse:Security header.
/// Dispatch the request through XData MessageMap — a BO with neither OnMessage/OnRequest
/// nor a MessageMap never runs at all — into a method that:
///   1. Instantiates the Web Service Client manually so SecurityOut can be set BEFORE InvokeMethod.
///   2. Builds the SAML assertion (see SAML-COS / SAML11-COS in examples/external-repos.md).
///   3. Wraps it in a <wsse:Security> header, passed via SecurityOut.
///   4. Calls InvokeMethod with the method name and arguments.
///
/// TYPE TRAP: SecurityOut is declared As %SOAP.Security.Header. Plain %SOAP.Security is a
/// PACKAGE, not a class — using it as a type fails to compile with
/// "ERROR #5373: Class '%SOAP.Security' ... does not exist".
///
/// The BO exposes a SAMLCredentials setting (alias of an X509 credentials configuration in IRIS)
/// so the cert used to sign the SAML can be changed per-environment without code change.
///
/// CRITICAL CONSTRAINT (§11.2): the SAML assertion must declare ALL its own XML namespaces.
/// Once the receiver extracts it from the SOAP envelope, it is processed by a separate
/// module that does not see the parent envelope's xmlns: declarations.
///
/// Request class: ch11_security/saml2-invoke-request.cls (Demo.SAML.MSG.InvokeReq).
Class Demo.SAML.BO.SoapClient Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";

/// Alias of an X509 credentials configuration in IRIS — the certificate the SAML is
/// signed with, swappable per environment without a code change.
Property SAMLCredentials As %String(MAXLEN = 128);

Parameter SETTINGS = "SAMLCredentials";

/// Without this the BO never dispatches: InvokeWithSAML would never be called.
XData MessageMap
{
<MapItems>
  <MapItem MessageType="Demo.SAML.MSG.InvokeReq">
    <Method>InvokeWithSAML</Method>
  </MapItem>
</MapItems>
}

Method InvokeWithSAML(pRequest As Demo.SAML.MSG.InvokeReq, Output pResponse As Ens.Response) As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM tHeader as %SOAP.Security.Header
    #DIM tResult as %String = ""
    #DIM errObj as %Exception.AbstractException
    try {
        // Generated SOAP client proxy — see §1.1 for the <Pkg>.<SubPkg>.WSC<Name> rule.
        Set ..Adapter.WebServiceClientClass = "Demo.SAML.WSCPartner"

        ///<initials><date>+: instantiate the Web Service Client to attach a SAML header
        Set ..Adapter.%Client = $classmethod(..Adapter.WebServiceClientClass, "%New")
        Set tSC = ..GenSecurityHeader(pRequest.SAMLAttributes, .tHeader)
        // `Quit:$$$ISERR(tSC) tSC` here would be #1043 "QUIT argument not allowed":
        // an argumented QUIT is illegal inside a TRY block. Guard here, act after the TRY.
        If $$$ISOK(tSC) {
            Set ..Adapter.%Client.SecurityOut = tHeader
            Set tSC = ..Adapter.InvokeMethod("methodName", .tResult, pRequest.Arg1, pRequest.Arg2)
        }
        ///<initials><date>-
    } catch (errObj) {
        Set tSC = errObj.AsStatus()
    }
    Quit:$$$ISERR(tSC) tSC

    Set pResponse = ##class(Ens.StringResponse).%New(tResult)
    Quit $$$OK
}

/// Build a wsse:Security header containing a SAML 2.0 assertion.
/// Hook — a subclass MUST override this. Implementation: see intersystems-ib/SAML-COS
/// (covers the Latin-1 charset bug, §11.1).
/// Deliberately NOT [ Abstract ]: an Abstract method invoked from a concrete class returns
/// "", and $$$ISERR("") is true, so the caller propagates an empty, unreadable %Status.
/// Returning a real error names the contract instead.
Method GenSecurityHeader(pSAMLAttributes As %String, Output pHeader As %SOAP.Security.Header) As %Status
{
    Set pHeader = ##class(%SOAP.Security.Header).%New()
    Quit $$$ERROR($$$GeneralError, ..%ClassName(1)_" must override GenSecurityHeader()")
}

}
