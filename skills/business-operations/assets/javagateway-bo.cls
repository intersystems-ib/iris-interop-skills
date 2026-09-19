/// Rule: BestPractices_Interop_IRIS.md §6.6 "Java integration via JavaGateway"
/// Validity: Still valid; flag as "Use sparingly in 2025+".
/// Severity: Medium.
///
/// Pattern: when a third-party library is only available as Java (e.g. a legacy
/// vendor SAML module or other vendor JAR) call it from Ensemble via the JavaGateway.
///
/// Steps:
///   1. Deploy the JAR to a fixed directory on the IRIS host (e.g. /opt/vendor/).
///   2. Use Studio -> Tools -> Java Gateway Wizard to generate ObjectScript proxy classes.
///   3. Write a BO that extends EnsLib.JavaGateway.AbstractOperation (this class).
///   4. Add the JAR to the JavaGateway classpath via the production component's
///      "Parametros adicionales" setting.
///
/// Two things a BO of this shape gets wrong easily:
///   - The gateway connection property declared by EnsLib.JavaGateway.AbstractOperation
///     is ..JavaGateway (type EnsLib.JavaGateway.JavaGateway). There is no
///     ..%GatewayConnection - referencing it fails to compile with MPP5376.
///   - Without an XData MessageMap (or an OnMessage override) nothing ever dispatches
///     to the method: see business-operations §"Common pitfalls".
///
/// Ens.StringContainer is used as request and response body only to keep the example
/// self-contained; a real integration defines its own <Pkg>.MSG.<Name>Req/Rsp classes.
///
/// In 2025+, prefer external services or ObjectScript reimplementation.
/// (The 2017+ SAML JavaGateway pattern was superseded by the public
/// intersystems-ib/SAML-COS ObjectScript implementation - see external-repos.md.)
Class Example.Adapters.BO.JavaGateway Extends EnsLib.JavaGateway.AbstractOperation
{

/// Setting: classpath addition for the JAR. Configure in production XML or Portal.
Parameter SETTINGS = "JavaClassPath";

Property JavaClassPath As %String(MAXLEN = 1024) [ InitialExpression = "/opt/vendor/vendor.jar" ];

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringContainer">
    <Method>CallVendorMethod</Method>
  </MapItem>
</MapItems>
}

Method CallVendorMethod(pRequest As Ens.StringContainer, Output pResponse As Ens.StringContainer) As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM tProxy as %ObjectHandle
    #DIM errObj as %Exception.AbstractException
    try {
        // Wizard-generated proxy class, here named "com.vendor.MyService".
        // ..JavaGateway is inherited from EnsLib.JavaGateway.AbstractOperation.
        set tProxy = ##class(com.vendor.MyService).%New(..JavaGateway)

        // The Java method to invoke (signature matches the generated proxy).
        set pResponse = ##class(Ens.StringContainer).%New()
        set pResponse.StringValue = tProxy.someJavaMethod(pRequest.StringValue)
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    quit tSC
}

}
