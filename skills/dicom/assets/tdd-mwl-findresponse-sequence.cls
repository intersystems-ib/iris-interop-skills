/// Rule: BestPractices_Interop_IRIS.md §15.7 "A C-FIND reply is N Pending then exactly one terminal status — including when there are zero rows"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the omission this guards leaves no error anywhere to find).
///
/// Pattern: the oracle for `bp-mwl-findresponse-sequence.cls`. It asserts the reply SEQUENCE, which is the
/// part that goes wrong, and needs no modality, no association and no DICOM document to do it — that is
/// why the sequence lives in a pure method.
///
/// THE ZERO-ROW CASE IS THE ONE WORTH HAVING. Every wrong implementation gets 1 and N right and zero
/// wrong, because "loop over the matches and send a terminal when you have sent some" reads as correct.
///
/// AND A DRIFT ALARM ON THE PLATFORM. `TestPlatformStillHasNoPendingMacro` compiles a throwaway class
/// referencing `$$$Pending` and asserts the compile FAILS. If a future IRIS adds the macro, this test
/// fails — which is exactly when §15.7 should stop telling people to write the literal.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=482  6 methods, 0 failed
///     terminal only sent when matches existed     run=483  1 failed -- ZeroRowsStillSends...
///     terminal dropped entirely                   run=484  3 failed
///     terminal goes FIRST instead of last         run=485  2 failed
///     ReplyCount forgets the terminal             run=486  1 failed
///     IsTerminal tests equality with Success      run=487  1 failed
///     Pending is 0xFF00 instead of 0xFF01         run=488  3 failed
///     reverted                                    run=489  6 methods, 0 failed
///
/// MUTATION 1 IS THE ONE THAT JUSTIFIES THIS SUITE. Guarding the terminal reply on `pRowCount > 0` is
/// caught by `ZeroRowsStillSendsOneTerminalReply` and by NOTHING ELSE -- 1 row and N rows both still look
/// correct. That is the shape of the real defect, and it is why the zero-row case is tested first.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.MwlFindResponseSequence", namespace="<NS>")
Class Example.Tests.MwlFindResponseSequence Extends %UnitTest.TestCase
{

Parameter RESPONDER As STRING = "Example.BP.MwlFindResponder";

Parameter PROBE As STRING = "ExampleMwlProbe.PendingMacro";

/// THE CASE EVERY WRONG IMPLEMENTATION GETS WRONG: no matches still sends one terminal reply.
Method TestZeroRowsStillSendsOneTerminalReply() As %Status
{
    Set tSequence = $ClassMethod(..#RESPONDER, "StatusSequence", 0)
    Do $$$AssertEquals($ListLength(tSequence), 1, "zero matches produces exactly ONE reply, not none")
    Do $$$AssertEquals($List(tSequence, 1), 0, "and that reply carries Success (0), so the modality knows the query ended")
    Do $$$AssertEquals($ClassMethod(..#RESPONDER, "ReplyCount", 0), 1, "the reply count for zero matches is 1")
    Quit $$$OK
}

/// One match: one Pending, then the terminal.
Method TestOneRowSendsPendingThenTerminal() As %Status
{
    Set tSequence = $ClassMethod(..#RESPONDER, "StatusSequence", 1)
    Do $$$AssertEquals($ListLength(tSequence), 2, "one match produces two replies")
    Do $$$AssertEquals($List(tSequence, 1), 65281, "the first is Pending (65281 = 0xFF01)")
    Do $$$AssertEquals($List(tSequence, 2), 0, "and the second is the terminal Success")
    Quit $$$OK
}

/// N matches: N Pending then exactly one terminal, and the terminal is LAST.
Method TestNRowsEndWithExactlyOneTerminal() As %Status
{
    Set tRows = 5
    Set tSequence = $ClassMethod(..#RESPONDER, "StatusSequence", tRows)
    Do $$$AssertEquals($ListLength(tSequence), tRows + 1, "five matches produce six replies -- always one more than the match count")
    // Count the terminals, and check where the one is.
    Set tTerminals = 0, tLastIsTerminal = 0
    For i = 1:1:$ListLength(tSequence) {
        Set tStatus = $List(tSequence, i)
        If $ClassMethod(..#RESPONDER, "IsTerminal", tStatus) {
            Set tTerminals = tTerminals + 1
            Set tLastIsTerminal = (i = $ListLength(tSequence))
        }
    }
    Do $$$AssertEquals(tTerminals, 1, "EXACTLY one terminal status in the sequence, found " _ tTerminals)
    Do $$$AssertTrue(tLastIsTerminal, "and it is the last reply, not one in the middle")
    Quit $$$OK
}

/// The two numbers are what the protocol says, and they differ.
Method TestTheStatusValuesAreTheProtocolOnes() As %Status
{
    Do $$$AssertEquals($Parameter(..#RESPONDER, "STATUSPENDING"), 65281, "Pending is 65281, which is 0xFF01 -- matches continuing, optional keys unsupported")
    Do $$$AssertEquals($Parameter(..#RESPONDER, "STATUSSUCCESS"), 0, "Success is 0")
    // 0xFF01 stated as arithmetic, so the hex claim in the header is checkable rather than asserted.
    Do $$$AssertEquals(65281, (255 * 256) + 1, "65281 really is 0xFF01")
    Quit $$$OK
}

/// `IsTerminal` is "not Pending", not "equals Success" -- a failure status also ends the query.
Method TestAnyNonPendingStatusIsTerminal() As %Status
{
    Do $$$AssertNotTrue($ClassMethod(..#RESPONDER, "IsTerminal", 65281), "Pending is NOT terminal")
    Do $$$AssertTrue($ClassMethod(..#RESPONDER, "IsTerminal", 0), "Success is terminal")
    // 0xA700 = Refused: Out of Resources, and 0xC000 = Unable to process. Both END the query.
    Do $$$AssertTrue($ClassMethod(..#RESPONDER, "IsTerminal", 42752), "a Refused status (0xA700) is terminal too")
    Do $$$AssertTrue($ClassMethod(..#RESPONDER, "IsTerminal", 49152), "and so is a failure status (0xC000) -- which is why the test is 'not Pending'")
    // POSITIVE CONTROL: 0xFF00, the OTHER Pending value, is the case a naive equals-65281 check breaks on.
    Do $$$AssertTrue($ClassMethod(..#RESPONDER, "IsTerminal", 65280), "NOTE: 0xFF00 is also a Pending status in DICOM, and this responder treats it as terminal because it only ever SENDS 0xFF01 -- a responder that RECEIVES replies must test both")
    Quit $$$OK
}

/// DRIFT ALARM: the platform still offers no macro for these numbers.
Method TestPlatformStillHasNoPendingMacro() As %Status
{
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tClass = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tClass.Super = "%RegisteredObject"
    Set tClass.IncludeCode = "EnsDICOM"
    Set tMethod = ##class(%Dictionary.MethodDefinition).%New()
    Set tMethod.Name = "Go"
    Set tMethod.ReturnType = "%Status"
    Do tMethod.Implementation.WriteLine("    Set x = $$$Pending")
    Do tMethod.Implementation.WriteLine("    Quit $$$OK")
    Do tClass.Methods.Insert(tMethod)
    Do $$$AssertStatusOK(tClass.%Save(), "the probe class saved")
    Set tSC = $System.OBJ.Compile(..#PROBE, "-d")
    Do $$$AssertNotTrue($$$ISOK(tSC), "$$$Pending is still NOT defined by EnsDICOM.inc -- so the literal is the only option")
    // POSITIVE CONTROL: with the SAME include, a macro that DOES exist compiles -- so the failure above
    // is about $$$Pending and not about the include being unreachable from a generated class.
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Set tOk = ##class(%Dictionary.ClassDefinition).%New(..#PROBE)
    Set tOk.Super = "%RegisteredObject"
    Set tOk.IncludeCode = "EnsDICOM"
    Set tOkMethod = ##class(%Dictionary.MethodDefinition).%New()
    Set tOkMethod.Name = "Go"
    Set tOkMethod.ReturnType = "%Status"
    Do tOkMethod.Implementation.WriteLine("    Set x = $$$MsgTyp2Str(1)")
    Do tOkMethod.Implementation.WriteLine("    Quit $$$OK")
    Do tOk.Methods.Insert(tOkMethod)
    Do $$$AssertStatusOK(tOk.%Save(), "the control probe saved")
    Do $$$AssertStatusOK($System.OBJ.Compile(..#PROBE, "-d"), "POSITIVE CONTROL: $$$MsgTyp2Str from the same include DOES compile")
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Do $System.OBJ.Delete(..#PROBE, "-d")
    Quit $$$OK
}

}
