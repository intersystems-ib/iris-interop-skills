/// Rule: BestPractices_Interop_IRIS.md §3.4 "SOAP carrying CDA / HL7 as MessageBody — the canonical pattern"
/// Validity: Still valid.
/// Severity: High.
///
/// BO half of the §3.4 pattern: pushes an HL7 message into the vendor SOAP service through
/// the patched proxy in `ch03_cda/soap-messagebody-hl7-proxy.cls`.
/// Subclasses EnsLib.HL7.Operation.SOAPOperation (copy it as needed if you must patch it).
///
/// Named `Demo.Vendor.BO.AcceptMessage`, not `Demo.Vendor.BO`: the convention is
/// `<Pkg>.<Tipo>.<Nombre>` (skills/interop), so the Tipo goes in the middle and the class
/// always carries a Name. The production item name is then `BO.AcceptMessage`.
Class Demo.Vendor.BO.AcceptMessage Extends EnsLib.HL7.Operation.SOAPOperation
{

/// Point the adapter at the patched proxy.
Method OnInit() As %Status
{
    set ..Adapter.WebServiceClientClass = "Demo.Vendor.WSC.AcceptMessageProxy"
    quit $$$OK
}

/// Override the operation method - default would call Send().
///
/// SIGNATURE TRAP: the superclass fixes this as
/// `pRequest:EnsLib.HL7.Message, *pResponse:EnsLib.HL7.Message`. Ens.Response is NOT a
/// subclass of EnsLib.HL7.Message, so the intuitive `Output pResponse As Ens.Response`
/// fails to compile with "ERROR #5478: Keyword signature error ... must be
/// 'EnsLib.HL7.Message,EnsLib.HL7.Message'". The response type is not yours to choose.
Method OnMessage(pRequest As EnsLib.HL7.Message, Output pResponse As EnsLib.HL7.Message) As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM tStream as %Stream.GlobalCharacter
    #DIM tResponseString as %String
    set tStream = ##class(%Stream.GlobalCharacter).%New()
    set tSC = pRequest.OutputToLibraryStream(tStream)
    quit:$$$ISERR(tSC) tSC

    set tSC = ..Adapter.InvokeMethod("acceptMessage", .tResponseString, tStream)
    // The vendor returns a plain acknowledgement string, not an HL7 message, and pResponse
    // is typed EnsLib.HL7.Message by the superclass. Leave it unset rather than forcing a
    // foreign type in: parse tResponseString into an EnsLib.HL7.Message here only if the
    // service really does answer with HL7.
    quit tSC
}

}
