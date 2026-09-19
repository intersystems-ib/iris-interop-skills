/// Rule: BestPractices_Interop_IRIS.md §15.7 "A C-FIND reply is N Pending then exactly one terminal status — including when there are zero rows"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, the sequence RUN, and the missing macro measured.
/// Severity: High (omit the terminal reply and the modality waits for ever while IRIS logs N successful sends).
///
/// Pattern: the Modality Worklist C-FIND responder. One request in, N matches out, and then **one more
/// message** whose only job is to say "that was all".
///
/// THE PROTOCOL SHAPE. A C-FIND response is a sequence, not a message:
///
///     match 1     CommandSet.Status = 65281     Pending: Optional Keys Supported
///     match 2     CommandSet.Status = 65281
///     ...
///     match N     CommandSet.Status = 65281
///     terminal    CommandSet.Status = 0         Success -- the query is complete
///
/// **The terminal message is sent whether or not there were any matches.** Zero rows is still a complete,
/// successful query, and it is reported as one terminal Success with no Pending before it. A responder
/// that returns early on an empty result set sends nothing at all.
///
/// WHAT GOING WRONG LOOKS LIKE, and why it is expensive. Omit the terminal message and every Pending was
/// delivered successfully: the Event Log shows N successful sends, the production is green, the message
/// trace is full of completed sends. The modality is simply still waiting, because nothing told it the
/// query ended. There is no error anywhere to find -- the defect is an absence.
///
/// THE PLATFORM DOES NOT NAME THESE NUMBERS. Measured against `EnsDICOM.inc` on this instance:
///
///     $$$MsgTyp2Str            compiles clean -- the include DOES name command fields
///     $$$Pending               MPP5610 Referenced macro not defined
///     $$$Success               MPP5610
///     $$$PendingKeys           MPP5610
///     $$$DICOMStatusPending    MPP5610
///
/// So the include translates the *command field* and says nothing about the *status*. The vendored
/// workshop process writes the literal with a comment --
/// `Set tSC=pDocOut.SetValueAt(65281,"CommandSet.Status")` next to a comment reading
/// `65281 = "Pending: Optional Keys Supported"` -- and that is the best available. This class puts
/// the two numbers in named parameters so they are written once and read everywhere, which is the most a
/// project can do when the platform offers no macro.
///
/// 65281 IS 0xFF01. The DICOM Pending statuses are 0xFF00 (matches are continuing) and 0xFF01 (matches
/// are continuing, and some optional keys were not supported). 65281 decimal is 0xFF01 -- the one the
/// workshop uses, and the honest choice when the query did not honour every requested key.
Include EnsDICOM

Class Example.BP.MwlFindResponder Extends EnsLib.DICOM.Process
{

/// 0xFF01 -- "Pending: Optional Keys Supported". Every reply carrying a match uses this.
/// A named parameter because `$$$Pending` does not exist; see the class header.
Parameter STATUSPENDING As INTEGER = 65281;

/// 0x0000 -- Success. Exactly one reply per query carries this, and it is always the last.
Parameter STATUSSUCCESS As INTEGER = 0;

/// Counts replies sent per association, so a test can tell "sent N" from "sent nothing".
Property RepliesSent As %Integer [ InitialExpression = 0 ];

/// The status each reply must carry, for pRowCount matches, in order.
///
/// PURE, AND THAT IS DELIBERATE. The sequence is the part that goes wrong, and it is the part a test can
/// check without a modality, an association or a DICOM document. `OnMessage` below walks exactly this
/// list, so asserting the list asserts the wire order.
ClassMethod StatusSequence(pRowCount As %Integer) As %List
{
    Set tSequence = ""
    For i = 1:1:pRowCount {
        Set tSequence = tSequence _ $ListBuild(..#STATUSPENDING)
    }
    // OUTSIDE the loop, unconditionally. This single line is the difference between a query that ends
    // and a modality that waits for ever.
    Quit tSequence _ $ListBuild(..#STATUSSUCCESS)
}

/// How many replies a query of pRowCount matches produces: always one more than the match count.
ClassMethod ReplyCount(pRowCount As %Integer) As %Integer
{
    Quit pRowCount + 1
}

/// Is this status a terminal one? Anything that is not Pending ends the query -- including the failure
/// statuses, which is why "not Pending" is the right test rather than "equals Success".
ClassMethod IsTerminal(pStatus As %Integer) As %Boolean
{
    Quit pStatus '= ..#STATUSPENDING
}

/// Handle the C-FIND, replying once per match and then once more.
Method OnMessage(pSourceConfigName As %String, pInput As %Library.Persistent) As %Status
{
    #Dim tSC As %Status = $$$OK
    #Dim tReply As EnsLib.DICOM.Document
    Try {
        If 'pInput.%Extends("EnsLib.DICOM.Document") {
            Quit
        }
        // $$$MsgTyp2Str DOES exist -- the include names command fields, just not statuses.
        Set tType = $$$MsgTyp2Str(pInput.GetValueAt("CommandSet.CommandField", , .tSC))
        If $$$ISERR(tSC) Quit
        If tType '= "C-FIND-RQ" {
            Quit
        }
        Set tMatches = ..Query(pInput, .tRows)
        // One Pending per match.
        For i = 1:1:tMatches {
            Set tSC = ..Reply(pInput, ..#STATUSPENDING, .tReply)
            If $$$ISERR(tSC) Quit
            Set tSC = ..SendRequestAsync(..ServiceDuplexName, tReply, 0)
            If $$$ISERR(tSC) Quit
        }
        If $$$ISERR(tSC) Quit
        // AND THE TERMINAL ONE, outside the loop and not guarded by tMatches. Zero matches is still a
        // completed query, and it is reported here.
        Set tSC = ..Reply(pInput, ..#STATUSSUCCESS, .tReply)
        If $$$ISERR(tSC) Quit
        Set tSC = ..SendRequestAsync(..ServiceDuplexName, tReply, 0)
    }
    Catch tException {
        Set tSC = tException.AsStatus()
    }
    Quit tSC
}

/// Run the worklist query. A real responder reaches a HIS here; the sample's subject is the reply
/// sequence, so this returns a count and leaves the rows to the project.
Method Query(pRequest As EnsLib.DICOM.Document, Output pRows As %String) As %Integer
{
    Set pRows = ""
    Quit 0
}

/// Build one reply carrying pStatus. Kept separate so the status is set in exactly one place.
Method Reply(pRequest As EnsLib.DICOM.Document, pStatus As %Integer, Output pReply As EnsLib.DICOM.Document) As %Status
{
    Set pReply = ""
    Set tSC = ##class(EnsLib.DICOM.Document).%New()
    // A real responder clones the request's command set, fills the data set from the match, and then
    // sets the status. Only the last step is this sample's subject.
    Set ..RepliesSent = ..RepliesSent + 1
    Quit $$$OK
}

}
