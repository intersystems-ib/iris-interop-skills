/// Rule: BestPractices_Interop_IRIS.md §6.1.4 "Required flags on generated properties break the call"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Sibling of soap-required-flag-drop.cls. The SOAP Wizard emits one class per WSDL
/// complex type; Example.Vendor.WSC.SAPRequest references this one through its
/// Patient property, so the §6.1.4 example only compiles with this class present.
///
/// Kept deliberately small - the same "drop the Required flag" patch applies here,
/// documented with the §6.1.7 marker convention.
Class Example.Vendor.WSC.SAPPatient Extends (%SerialObject, %XML.Adaptor)
{

/// Was: Property PatientId As %String(MAXLEN = 40) [ Required ];
///<initials>20200310: dropped Required flag; SAP accepts partial messages.
Property PatientId As %String(MAXLEN = 40);

Property FamilyName As %String(MAXLEN = 60);

Property GivenName As %String(MAXLEN = 60);

}
