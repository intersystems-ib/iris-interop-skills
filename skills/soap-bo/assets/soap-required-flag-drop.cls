/// Rule: BestPractices_Interop_IRIS.md §6.1.4 "Required flags on generated properties break the call"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Symptom: vendor WS chokes when IRIS validates the message has all required fields
/// and refuses to send because one is missing - yet the WS would have accepted the
/// partial message.
///
/// Fix: drop REQUIRED=1 from the generated SOAP type properties.
/// Edit the wizard-generated class; document the patch in the header comment
/// (convention: every edit prefixed `///<initials><date><tag>:` — see §6.1.7).
///
/// The referenced complex type lives in its own file, as the wizard generates it:
/// soap-required-flag-drop-sappatient.cls (Example.Vendor.WSC.SAPPatient).
Class Example.Vendor.WSC.SAPRequest Extends (%SerialObject, %XML.Adaptor)
{

/// Was: Property OrderId As %String(MAXLEN = 40) [ Required ];
///<initials>20200310: dropped Required flag; SAP accepts partial messages.
Property OrderId As %String(MAXLEN = 40);

/// Was: Property Patient As Example.Vendor.WSC.SAPPatient [ Required ];
///<initials>20200310: dropped Required flag.
Property Patient As Example.Vendor.WSC.SAPPatient;

}
