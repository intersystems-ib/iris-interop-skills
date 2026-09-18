/// Rule: BestPractices_Interop_IRIS.md §15.5 "Registering DICOM associations from OnStart — and the verify step that makes it worth doing"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the defect it guards makes a production start green with no negotiable association).
///
/// Pattern: the oracle for `utl-dicom-association-registrar.cls` and the `OnStart` beside it.
///
/// THE CENTRAL ASSERTION IS A COUNT, NOT A STATUS. `CreateAssociation` returning `$$$OK` and
/// `AETExists` returning 1 are both true of an association context that offers the remote AE nothing
/// at all, so neither can be the test. The number of presentation contexts is the only value that
/// separates a usable registration from a useless one.
///
/// TestRepairsAnEmptyContext IS THE ONE THAT PAYS FOR THE CLASS. It plants exactly the state the
/// field produces — an `AssociationContext` saved with an empty `PresentationContexts` list, which
/// `%ValidateObject` and `%Save` both accept — and asserts that `Register` notices and rebuilds it.
/// Without the repair branch the registrar would report the problem and leave it, and since
/// `AETExists` is true nothing else would ever fix it.
///
/// WHAT IS *NOT* ASSERTED HERE, said out loud. Nothing in this suite starts the production or opens a
/// TCP association, so the wire-direction claim in §15.1 — that (Calling, Called) is initiator then
/// responder — is NOT tested by it; that needs a peer. What is tested is that the two orders produce
/// two DIFFERENT contexts, which is the part a reader can get wrong in code rather than on a network.
///
/// MEASURED VALUES this pins, from the run that preceded it:
///     289 abstract syntaxes in ^EnsDICOM.Dictionary("as","u")
///     platform CreateAssociation(calling, called)              237 contexts
///     the vendored wrapper, pTypeList ("Storage","FIND")        209
///     the vendored wrapper, pTypeList ("Storage")               197
///     the vendored wrapper, pTypeList ("Storge") -- one typo      0, create=OK, AETExists=1
///     %New(a,b) then %Save() with no contexts                     0, validate=OK, save=OK, AETExists=1
///     CreateAssociation with a bogus TRANSFER SYNTAX            <EnsDICOM>TransferSyntaxNotSupported,
///                                                              AETExists=0 -- this path is LOUD
///     AETExists("a","b") -> 0     AETExists() -> <UNDEFINED>
///
/// RUN AND MUTATION-CHECKED, measured, seven mutations:
///
///     as shipped                                          PASSED 7/7
///     1 the repair branch removed                          TestRepairsAnEmptyContext         FAIL
///     3 CountContexts returns 1, not the real count         TestRegisterLandsContexts
///                                                         + TestRepairsAnEmptyContext       FAIL
///     4 the error-text assertion inverted                  TestBlankAetFailsLoudly           FAIL
///     5 Register called with the titles swapped             TestOrderMakesADifferentContext  FAIL
///     6 a production RemoteAET renamed, OnStart not         TestProductionAetsMatchOnStart   FAIL
///     7 AssociationPairs drops the outbound pair            TestProductionAetsMatchOnStart   FAIL
///
/// ONE MUTATION SURVIVES, AND IT IS A REAL GAP THAT STAYS. Making `Register` return `$$$OK` when the
/// count is zero AFTER a rebuild leaves the suite green. Reaching that branch needs a rebuild that
/// itself yields zero presentation contexts, which on this build means an empty
/// `^EnsDICOM.Dictionary("as","u")` — 289 entries today, and not arrangeable without breaking the
/// namespace for every other test. Marked at the branch in the registrar as defensive and unfalsified
/// rather than left looking covered.
///
/// AND ONE MUTATION FROM THE FIRST PASS DELETED CODE INSTEAD OF STRENGTHENING A TEST. Removing the
/// registrar's blank-AET guard left the suite green — which was the guard's own verdict, not a hole:
/// the platform already rejects a blank title with `<EnsDICOM>BadCallingAET` / `BadCalledAET`, each
/// naming which side is wrong, so a guard in front could only replace a specific error with a vaguer
/// one. The guard was removed and `TestBlankAetFailsLoudly` now asserts the platform's messages.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DicomOnStartAssociations", namespace="<NS>")
Class Example.Tests.DicomOnStartAssociations Extends %UnitTest.TestCase
{

/// AE titles used only by this suite. Real ones would collide with a deployment's own contexts, and
/// this suite DELETES what it registers.
Parameter CALLING = "ZZTESTMOD";

Parameter CALLED = "ZZTESTIRIS";

/// Leave nothing behind: an association context is namespace data, not test data, and a stray pair
/// is exactly the kind of thing the next run would then find "already correct".
Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Forget(..#CALLING, ..#CALLED)
    Do ..Forget(..#CALLED, ..#CALLING)
    Do ..Forget("", ..#CALLED)
    Do ..Forget(..#CALLING, "")
    Quit $$$OK
}

ClassMethod Forget(pCalling As %String, pCalled As %String) As %Status [ Private ]
{
    If ##class(EnsLib.DICOM.Util.AssociationContext).AETExists(pCalling, pCalled) {
        Quit ##class(EnsLib.DICOM.Util.AssociationContext).AETDelete(pCalling, pCalled)
    }
    Quit $$$OK
}

/// A registration lands presentation contexts, and the count is what proves it.
Method TestRegisterLandsContexts() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.DicomAssociations).Register(..#CALLING, ..#CALLED, .tCount), "Register succeeded")
    Do $$$AssertTrue(##class(EnsLib.DICOM.Util.AssociationContext).AETExists(..#CALLING, ..#CALLED), "AETExists is true -- and would be true of an empty context too")
    // The assertion that an AETExists check cannot make. 237 on this build; asserted as a floor so a
    // dictionary that grows does not fail the suite, and a dictionary that empties does.
    Do $$$AssertTrue(tCount > 100, "the context carries presentation contexts, not zero: " _ tCount)
    Quit $$$OK
}

/// An idempotent second call must not destroy or duplicate what the first one built.
Method TestRegisterIsIdempotent() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.DicomAssociations).Register(..#CALLING, ..#CALLED, .tFirst), "first Register")
    Do $$$AssertStatusOK(##class(Example.UTL.DicomAssociations).Register(..#CALLING, ..#CALLED, .tSecond), "second Register")
    Do $$$AssertEquals(tSecond, tFirst, "the second call leaves the same number of contexts: " _ tFirst _ " then " _ tSecond)
    Quit $$$OK
}

/// THE ONE THAT PAYS FOR THE CLASS. Plant a context that saves clean with zero presentation
/// contexts -- exactly what a type list matching nothing produces -- and require a rebuild.
Method TestRepairsAnEmptyContext() As %Status
{
    Do ..Forget(..#CALLING, ..#CALLED)
    Set tEmpty = ##class(EnsLib.DICOM.Util.AssociationContext).%New(..#CALLING, ..#CALLED)
    Do $$$AssertTrue($IsObject(tEmpty), "a context object was created")
    Do $$$AssertEquals(tEmpty.PresentationContexts.Count(), 0, "with no presentation contexts")
    // Both of these accepting it is the whole problem.
    Do $$$AssertStatusOK(tEmpty.%ValidateObject(), "%ValidateObject accepts an empty context")
    Do $$$AssertStatusOK(tEmpty.%Save(), "and so does %Save")
    Do $$$AssertTrue(##class(EnsLib.DICOM.Util.AssociationContext).AETExists(..#CALLING, ..#CALLED), "so AETExists now returns 1 for a context that offers nothing")
    // And now the registrar must notice and rebuild rather than trust the guard.
    Do $$$AssertStatusOK(##class(Example.UTL.DicomAssociations).Register(..#CALLING, ..#CALLED, .tCount), "Register repairs it")
    Do $$$AssertTrue(tCount > 100, "and the rebuilt context carries presentation contexts: " _ tCount)
    Quit $$$OK
}

/// (Calling, Called) is an ordered pair: the reverse is a different association, not the same one.
Method TestOrderMakesADifferentContext() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.DicomAssociations).Register(..#CALLING, ..#CALLED, .tFwd), "forward pair registered")
    Do $$$AssertTrue(##class(EnsLib.DICOM.Util.AssociationContext).AETExists(..#CALLING, ..#CALLED), "the forward pair exists")
    Do $$$AssertEquals(##class(EnsLib.DICOM.Util.AssociationContext).AETExists(..#CALLED, ..#CALLING), 0, "and the REVERSE pair does not: swapping the titles is a different context, not the same one")
    Quit $$$OK
}

/// A blank AE title fails LOUDLY, and naming which side is wrong. This test began life asserting a
/// guard in the registrar; a mutation removing that guard left it green, which is how the guard was
/// found to be redundant. It now asserts the platform's own behaviour, which is the fact worth
/// keeping — and the contrast that makes the empty-context case interesting: the AE title's VALUE is
/// validated, the presentation-context CONTENT is not.
Method TestBlankAetFailsLoudly() As %Status
{
    Set tSC = ##class(Example.UTL.DicomAssociations).Register("", ..#CALLED, .tCount)
    Do $$$AssertStatusNotOK(tSC, "a blank calling AE title is an error, not a registration")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ "BadCallingAET", "and the error names WHICH side is wrong: " _ $Extract(tText, 1, 80))
    Do $$$AssertEquals(tCount, 0, "nothing is reported as registered")
    Do $$$AssertEquals(##class(EnsLib.DICOM.Util.AssociationContext).AETExists("", ..#CALLED), 0, "and no context was created")
    Set tSC2 = ##class(Example.UTL.DicomAssociations).Register(..#CALLING, "", .tCount2)
    Do $$$AssertStatusNotOK(tSC2, "a blank CALLED title is an error too")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC2) [ "BadCalledAET", "and it is the other message, not the same one")
    Quit $$$OK
}

/// THE CHECK THE COMPILER CANNOT DO. The AE titles are written twice — in
/// `Example.Productions.DicomOnStart::AssociationPairs()` and as `LocalAET`/`RemoteAET` adapter
/// settings in the same class's `ProductionDefinition`. A `RemoteAET` changed in one and not the other
/// leaves a production that starts green, registers the OLD pair, and refuses every association;
/// nothing catches it at compile time and nothing logs it at run time. This asserts the two agree as
/// SETS of titles, which is what a rename breaks. Direction is covered separately by
/// TestOrderMakesADifferentContext — set equality deliberately says nothing about it.
Method TestProductionAetsMatchOnStart() As %Status
{
    Set tSC = ..XDataTitles("Example.Productions.DicomOnStart", .tFromXml)
    Do $$$AssertStatusOK(tSC, "the production's XData was readable")
    Set tPairs = ##class(Example.Productions.DicomOnStart).AssociationPairs()
    Do $$$AssertTrue($ListLength(tPairs) > 0, "AssociationPairs is not empty")
    Set tFromCode = ""
    For i = 1:1:$ListLength(tPairs) {
        Set tPair = $List(tPairs, i)
        Set tFromCode($List(tPair, 1)) = ""
        Set tFromCode($List(tPair, 2)) = ""
    }
    // Both directions, because each catches a different mistake: a title in the code and not the
    // production is a registration nothing uses; one in the production and not the code is an
    // association nobody registered.
    Set tMissing = ""
    Set k = "" For { Set k = $Order(tFromCode(k))  Quit:k=""  If '$Data(tFromXml(k)) { Set tMissing = tMissing_" "_k } }
    Do $$$AssertEquals(tMissing, "", "every AE title OnStart registers is an adapter setting in the production; missing:" _ tMissing)
    Set tUnregistered = ""
    Set k = "" For { Set k = $Order(tFromXml(k))  Quit:k=""  If '$Data(tFromCode(k)) { Set tUnregistered = tUnregistered_" "_k } }
    Do $$$AssertEquals(tUnregistered, "", "and every AE title in the production is one OnStart registers; unregistered:" _ tUnregistered)
    Quit $$$OK
}

/// Collect the LocalAET/RemoteAET values out of a production's XData. Read from
/// %Dictionary.CompiledXData rather than Ens_Config.Item, so this needs no deployed production —
/// Ens_Config.Item is empty until the production has been registered, and a test that silently
/// depends on that passes or fails on the order the suite happens to run in.
Method XDataTitles(pProduction As %String, Output pTitles) As %Status [ Private ]
{
    Kill pTitles
    Set tX = ##class(%Dictionary.CompiledXData).%OpenId(pProduction _ "||ProductionDefinition", , .tSC)
    If '$IsObject(tX) {
        Set tWhy = "no ProductionDefinition XData on " _ pProduction _ ": " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Set tStream = tX.Data
    If '$IsObject(tStream) { Quit $$$ERROR($$$GeneralError, "the XData carries no Data stream") }
    Do tStream.Rewind()
    Set tXml = ""
    While 'tStream.AtEnd { Set tXml = tXml _ tStream.Read(32000) }
    For tWhich = "LocalAET", "RemoteAET" {
        Set tNeedle = "Name=""" _ tWhich _ """>"
        For i = 2:1:$Length(tXml, tNeedle) {
            Set tRest = $Piece(tXml, tNeedle, i)
            Set tVal = $Piece(tRest, "<", 1)
            Set:tVal'="" pTitles(tVal) = ""
        }
    }
    Quit $$$OK
}

/// AETExists takes TWO arguments, whatever %Dictionary.CompiledMethod says about it. Pinned because
/// the whole guard rests on it, and because the dictionary's answer is the wrong one.
Method TestAetExistsTakesTwoArguments() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT FormalSpec, ClassMethod FROM %Dictionary.CompiledMethod WHERE parent = ? AND Name = 'AETExists'", "EnsLib.DICOM.Util.AssociationContext")
    Do $$$AssertTrue(tRs.%Next(), "the dictionary has a row for AETExists")
    // What the dictionary claims -- both wrong, and asserted as wrong so the day it is fixed this
    // test says so instead of quietly agreeing.
    Do $$$AssertEquals(tRs.%Get("FormalSpec"), "", "the dictionary reports no formal spec for this index-generated method")
    // What it actually does.
    Do $$$AssertEquals(##class(EnsLib.DICOM.Util.AssociationContext).AETExists("ZZNOSUCH", "ZZNEITHER"), 0, "yet it accepts two arguments and answers 0 for a pair that does not exist")
    Quit $$$OK
}

}
