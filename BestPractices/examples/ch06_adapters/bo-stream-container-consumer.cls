/// Rule: BestPractices_Interop_IRIS.md §6.10 "File passthrough relay — Ens.StreamContainer, and the read that only works once"
/// Validity: Verified against IRIS for Health 2026.1 — the read behaviour below was executed.
/// Severity: High (a second read returns "" and reports nothing).
///
/// Pattern: a CUSTOM operation that consumes the relay's message. Reach for this only when the
/// prebuilt PassthroughOperation is not enough — you need to inspect, log, count or re-route the
/// content. The wiring is in production-file-passthrough.cls.
///
/// THE SILENT FAILURE, MEASURED. A %Stream keeps a read position, and `Read()` advances it. Run on
/// 2026.1 against a saved-and-reopened Ens.StreamContainer:
///
///     Read(100)            -> "line-1"
///     Read(100) again      -> ""            <-- no error, no warning, no Event Log entry
///     Rewind(), Read(100)  -> "line-1"
///
/// The empty string is the defect's whole signature. The shape that produces it is ordinary and
/// looks careful: log the content, then write it out. The log gets the data, the write gets "",
/// and the output file is created EMPTY — so the run looks successful and the failure surfaces
/// downstream, hours later, as "the file arrived but it's blank".
///
/// THE RULE: any method that reads a stream it did not create must `Rewind()` FIRST, not after.
/// After is a convention you have to remember at every exit path, including the error ones; before
/// is a single line that cannot be skipped. Rewinding a stream already at position 0 costs nothing.
///
/// A SEPARATE HOST IS NOT AT RISK. Message bodies travel between business hosts by id, so each host
/// %OpenId's its own instance at position 0 — the two-targets-one-message case is safe. The risk is
/// entirely WITHIN one method, or one object passed along in-process.
///
/// OriginalFilename IS THE ONLY LINK BACK TO THE SOURCE FILE. The container carries it, and
/// PassthroughOperation's `%f` substitution is just a read of this property. If you build the output
/// name yourself, read it from here — there is nothing else that knows it.
Class Example.BO.ArchiveStream Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.File.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Ens.StreamContainer is the relay's body type — verified against
/// EnsLib.File.PassthroughOperation's own OnMessage signature.
Method OnMessage(pRequest As Ens.StreamContainer, Output pResponse As Ens.StringContainer) As %Status
{
    Set tSC = $$$OK
    Try {
        If '$IsObject(pRequest.Stream) {
            Set tSC = $$$ERROR($$$GeneralError, "container carried no stream")
            Quit
        }

        // REWIND BEFORE READING. Not after. See the header: the caller may have read it already,
        // and there is no way to ask a stream whether it is at position 0.
        Do pRequest.Stream.Rewind()
        Set tSize = pRequest.Stream.Size
        Set tName = pRequest.OriginalFilename

        // Rewind AGAIN before handing the stream on, because the Size read above consumed nothing
        // but a content inspection would have. Cheap insurance at the boundary.
        Do pRequest.Stream.Rewind()
        Set tSC = ..Adapter.PutStream(tName, pRequest.Stream)
        Quit:$$$ISERR(tSC)

        Set pResponse = ##class(Ens.StringContainer).%New("archived " _ tName _ " (" _ tSize _ " bytes)")
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
