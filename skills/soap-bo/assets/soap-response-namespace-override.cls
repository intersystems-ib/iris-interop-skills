/// Rule: BestPractices_Interop_IRIS.md §6.1.6 "RESPONSENAMESPACE doesn't match what the vendor actually returns"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Symptom: the WSDL specifies one response namespace but the actual SOAP responses
/// come back with a different one.
///
/// Example:
///   WSDL says:     http://example.org/PrescriptionWS
///   Real response: http://prescription.ws.example.org
///
/// Fix: edit the generated proxy and override Parameter RESPONSENAMESPACE
/// to the actual value.
///
/// General rule: don't trust the WSDL - sniff the actual response (use ^ISCSOAP
/// per-BO tracing, §6.2), then adjust.
Class Demo.Vendor.WSC.PrescriptionWS Extends %SOAP.WebClient
{

/// Minimum viable %SOAP.WebClient parameters - the SOAP Wizard generates both from
/// the WSDL. Without SERVICENAME the class does not compile:
///   ERROR #6240: SERVICENAME must be specified by overriding the SERVICENAME parameter.
Parameter NAMESPACE = "http://example.org/PrescriptionWS";

Parameter SERVICENAME = "PrescriptionWS";

/// The point of this example (patch marked per §6.1.7).
///<initials>20171115: vendor returns a different response namespace than the WSDL declares.
/// WSDL: "http://example.org/PrescriptionWS"  -> actual:
Parameter RESPONSENAMESPACE = "http://prescription.ws.example.org";

}
