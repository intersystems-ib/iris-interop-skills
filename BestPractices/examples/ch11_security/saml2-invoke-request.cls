/// Rule: BestPractices_Interop_IRIS.md §11.3 "SAML 2.0 — attaching a custom security header to a generated SOAP BO"
/// Validity: Still valid.
/// Severity: High.
///
/// Sibling of ch11_security/saml2-custom-security-header.cls — the request that
/// Demo.SAML.BO.SoapClient routes on. A BO's XData MessageMap has to key on a concrete
/// message type, so without this class the BO has nothing to dispatch.
/// `%Persistent` is LEFTMOST deliberately: without it this message shares
/// `^Ens.MessageBodyD` with every other message type in the namespace, and no compile,
/// test or Event Log entry would ever say so (§5.10, and tdd-message-own-extent.cls).
Class Demo.SAML.MSG.InvokeReq Extends (%Persistent, Ens.Request)
{

/// Attributes the SAML assertion is built from (subject, issuer, roles, ...).
Property SAMLAttributes As %String(MAXLEN = 32000);

Property Arg1 As %String(MAXLEN = 1024);

Property Arg2 As %String(MAXLEN = 1024);

}
