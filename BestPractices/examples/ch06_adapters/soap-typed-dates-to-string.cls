/// Rule: BestPractices_Interop_IRIS.md §6.1.5 "Strongly-typed dates/times rejected by vendor; downgrade to %String"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Symptom: WSDL specifies xs:date / xs:time and the vendor server cannot actually
/// parse the typed values that IRIS sends.
///
/// Fix: change the generated property to %String. The transmitted lexical form
/// ("2020-03-02", "11:00:00") is correct anyway.
Class Example.Vendor.WSC.SAPDateRequest Extends (%SerialObject, %XML.Adaptor)
{

/// Was: Property AppointmentDate As %Date(XMLTYPE = "date");
///<initials>20200310: downgraded to %String; SAP cannot parse the typed xs:date.
Property AppointmentDate As %String(MAXLEN = 10);

/// Was: Property AppointmentTime As %Time(XMLTYPE = "time");
///<initials>20200310: downgraded to %String; SAP cannot parse the typed xs:time.
Property AppointmentTime As %String(MAXLEN = 8);

}
