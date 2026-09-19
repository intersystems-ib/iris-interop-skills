/// Rule: BestPractices_Interop_IRIS.md §15.6 "DICOM query/retrieve is a quartet, not a duplex pair — and the vendored snapshot's own reply leg dangles"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and started.
/// Severity: Medium (the stand-in); the wiring finding it serves is High.
///
/// Pattern: the duplex partner every `EnsLib.DICOM.Service.TCP` and `EnsLib.DICOM.Operation.TCP` item
/// needs. Three items in `production-dicom-query-retrieve.cls` use this one class, because the SUBJECT
/// of that sample is the wiring and one shared stand-in keeps the item graph readable.
///
/// WHAT IT DELIBERATELY DOES NOT DO. No C-FIND matching, no C-MOVE sub-operation accounting, no
/// presentation-context negotiation. Those belong to the real leg classes, and the vendored workshop tree
/// under `BestPractices/external/workshop-iris-dicom-interop` is the reference for them
/// (`DICOM.BP.QueryProcess`, `DICOM.BP.MoveProcess`, `DICOM.BP.StoreProcess`). Writing a half-credible
/// C-FIND here would invite it to be copied.
///
/// WHY A BUSINESS PROCESS AT ALL, rather than wiring the service straight to the operation. A DICOM duplex
/// item names ONE partner, and that partner has to hold the association state for the conversation --
/// which request the response belongs to, and when the conversation is finished. An operation cannot do
/// that for a service, so the pair is always service to process, never service to operation.
Class Example.BP.DicomLeg Extends Ens.BusinessProcess
{

/// Counts what arrived, per config name, so a test can tell "reached this leg" from "never called".
ClassMethod Seen(pConfigName As %String) As %Integer
{
    Quit +$Get(^Example.DicomLeg(pConfigName))
}

ClassMethod Reset() As %Status
{
    Kill ^Example.DicomLeg
    Quit $$$OK
}

Method OnRequest(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
    Set ^Example.DicomLeg(..%ConfigName) = $Increment(^Example.DicomLeg(..%ConfigName))
    // A real leg would inspect the document's command set and reply on its own duplex partner. This
    // one completes, which is enough for the wiring assertions beside it.
    Quit $$$OK
}

}
