/// Rule: BestPractices_Interop_IRIS.md §5.15 "A bare `%String` rejects, it does not truncate — and `MAXLEN=""` has a second ceiling"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: Medium (what it protects is a paragraph of prose that was wrong for the life of the plugin).
///
/// Pattern: the oracle for `Example.MSG.MaxLenBoundaries` in this directory. It exists because the
/// claim it settles had been asserted in prose at three separate skill sites, in opposite terms to
/// what the platform does, for every release until v1.36.0.
///
/// WHAT WAS WRONG, and why only a run could have caught it. `messages` and `soap-bo` said a bare
/// `%String` over 50 chars is "silently truncated on `%Save` (no error, the data is just gone)".
/// Measured: `%Save` returns `ERROR #7201`, `%ValidateObject()` returns the same `#7201`, an SQL
/// `INSERT` returns `SQLCODE=-104`, and the in-memory value after `Set` is the FULL length. There is
/// an error, and the data is not gone. Both halves of the sentence were false. No compile could have
/// found that — the wrong version and the right version are the same class; only executing the save
/// and reading the status apart tells them apart.
///
/// THE TESTS, and what dropping each one would let through:
///
///   TestFiftyIsFine              the positive control. Without it, every "rejected" assertion below
///                                could be produced by a save path that is simply broken, and the
///                                suite would be green for the wrong reason. A clean rejection is
///                                only evidence once the same path has been seen to accept.
///   TestFiftyOneIsRejected       the point. 51 chars -> #7201, one character over the boundary.
///   TestNothingIsTruncated       the half the prose got wrong that an error code alone does not
///                                cover: after Set, the in-memory value still holds every character,
///                                and after the failed save NO row exists. Not truncated, not
///                                partially stored -- refused.
///   TestValidateAgreesWithSave   %ValidateObject() gives the same verdict, so the check is
///                                available before you commit to a save.
///   TestSqlInsertAlsoRejects     a DIFFERENT path to the same column. Without it, "rejects" is only
///                                known for the object layer, and SQL is exactly where someone would
///                                expect a silent database-style truncation.
///   TestUnlimitedHoldsLargeText  MAXLEN="" really is unbounded in the range anyone will use --
///                                100,000 chars saved and read back identical.
///   TestCeilingValidatesButFails the second ceiling, and the only test here that asserts a
///                                DISAGREEMENT: at $$$MaxStringLength, %ValidateObject says OK and
///                                %Save fails #5002 <MAXSTRING>. Drop it and "MAXLEN='' is unbounded
///                                up to 3.6MB" reads as though the top of that range is usable.
///
/// MEASURED VALUES this test pins, from the run that preceded it:
///     bare 50   -> saved, read back 50          bare 51  -> #7201
///     bare 100  -> #7201, in-memory len 100     SQL 100  -> SQLCODE -104
///     MAXLEN="" 100,000 -> saved, read back 100,000
///     MAXLEN="" 3,600,000 -> saved              MAXLEN="" 3,641,144 -> validates OK, save #5002
///
/// RUN, AND MUTATION-CHECKED. Executed via `%UnitTest.Manager.RunTest("<suite>", "/nodelete")` with
/// `^UnitTestRoot` set to a directory on the IRIS server -- the only path measured to PERSIST
/// verdicts. (`RunOneTestCase` and `DebugRunTestCase` both execute and record nothing: measured
/// `methods=0 pass=0 fail=0` with all three result tables empty, which is itself the reason the
/// first reading of this suite proved nothing.)
///
///     as shipped                              methods=8  pass=8  fail=0
///     51 -> 50 in TestFiftyOneIsRejected       TestFiftyOneIsRejected      FAILS
///     ceiling asserts 7201 instead of 5002     TestCeilingValidatesButFails FAILS
///     in-memory length asserted as 50          TestNothingIsTruncated      FAILS
///     SQL expects SQLCODE 0                    TestSqlInsertAlsoRejects    FAILS
///     MAXLEN="" expects a rejection            TestUnlimitedHoldsLargeText FAILS
///
/// Each mutation reddens EXACTLY its own test and nothing else, so no assertion here is passing
/// for a reason other than the one it names. All six versions compile, so tier 2 is green on every
/// one of them -- the compile distinguishes none of this.
///
/// TWO TRAPS HIT WHILE READING THOSE VERDICTS, both of which produced a confident wrong answer and
/// are now written up in §5.14 and fixed in `unittest-sqlproc-result-reader.cls`:
/// results ACCUMULATE across runs, so an unscoped reader summed five runs and reported `methods=40`
/// with a reverted mutation still showing red; and `MAX(ID)` picks the wrong run, because the ID is
/// the string `<instance>||<suite>||<case>` and `'9||…'` sorts above `'13||…'`.
///
/// ONE COST WORTH KNOWING BEFORE YOU RUN IT. TestCeilingValidatesButFails allocates a 3.6 MB string
/// twice. That is deliberate -- the disagreement only appears at the ceiling -- but it makes this
/// the most expensive test in the bank, and it is why the assertion is one test rather than a sweep.
/// CI never runs it: tier 2 compiles this class and stops.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.MaxLenTruncation", namespace="<NS>")
Class Example.Tests.MaxLenTruncation Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. This suite touches no production; TestControl neutralises the
/// start/stop this superclass would otherwise drive.
Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// A string of exactly pLen characters.
ClassMethod Fill(pLen As %Integer, pChar As %String = "x") As %String [ Private ]
{
    Quit $Translate($Justify("", pLen), " ", pChar)
}

/// POSITIVE CONTROL. The boundary value that must SUCCEED -- without this, a broken save path would
/// make every rejection assertion below pass for the wrong reason.
Method TestFiftyIsFine()
{
    Set tMsg = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tMsg.Bare = ..Fill(50)
    Do $$$AssertStatusOK(tMsg.%Save())

    Set tBack = ##class(Example.MSG.MaxLenBoundaries).%OpenId(tMsg.%Id())
    Do $$$AssertEquals($Length(tBack.Bare), 50, "50 chars must survive a round trip intact")
}

/// One character over the default MAXLEN.
Method TestFiftyOneIsRejected()
{
    Set tMsg = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tMsg.Bare = ..Fill(51)
    Set tSC = tMsg.%Save()

    Do $$$AssertStatusNotOK(tSC)
    Do $$$AssertEquals($System.Status.GetErrorCodes(tSC), 7201, "the refusal must be #7201, the datatype error that names the field")
}

/// The half the prose got wrong: nothing is shortened, and nothing is partially stored.
Method TestNothingIsTruncated()
{
    Set tBefore = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tBefore.Bare = ..Fill(100)

    // In memory the value is untouched -- the property setter does not cut it.
    Do $$$AssertEquals($Length(tBefore.Bare), 100, "the in-memory value must keep all 100 chars")

    Set tSC = tBefore.%Save()
    Do $$$AssertStatusNotOK(tSC)

    // And the object was never given an id, so there is no partially-stored row to find.
    Do $$$AssertEquals(tBefore.%Id(), "", "a rejected save must leave no row behind")
}

/// The same verdict is available without committing to a save.
Method TestValidateAgreesWithSave()
{
    Set tMsg = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tMsg.Bare = ..Fill(100)
    Set tVSC = tMsg.%ValidateObject()

    Do $$$AssertStatusNotOK(tVSC)
    Do $$$AssertEquals($System.Status.GetErrorCodes(tVSC), 7201, "%ValidateObject must give the same #7201 as %Save")
}

/// A different path into the same column -- and the one where a database-style silent truncation
/// would be least surprising. It is not silent here either.
Method TestSqlInsertAlsoRejects()
{
    Set tVal = ..Fill(100)
    &sql(INSERT INTO Example_MSG.MaxLenBoundaries (Bare) VALUES (:tVal))

    Do $$$AssertNotEquals(SQLCODE, 0, "SQL must refuse an over-length value too")
    Do $$$AssertEquals(SQLCODE, -104, "the refusal must be SQLCODE -104, a field validation failure")
}

/// MAXLEN="" across the range anyone will actually use.
Method TestUnlimitedHoldsLargeText()
{
    Set tBig = ..Fill(100000, "y")
    Set tMsg = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tMsg.Unlimited = tBig
    Do $$$AssertStatusOK(tMsg.%Save())

    Set tBack = ##class(Example.MSG.MaxLenBoundaries).%OpenId(tMsg.%Id())
    Do $$$AssertEquals($Length(tBack.Unlimited), 100000, "MAXLEN='' must store 100,000 chars")
    Do $$$AssertEquals(tBack.Unlimited, tBig, "and return them unchanged")
}

/// THE SECOND CEILING. The only assertion here that pins a DISAGREEMENT between two APIs: at
/// $$$MaxStringLength the value is a legal string and validates clean, and the save still fails --
/// because the row is assembled into one global node with the object's other data, and the assembly
/// overflows. Allocates 3.6 MB; see the header.
Method TestCeilingValidatesButFails()
{
    Set tAtCeiling = ..Fill($$$MaxStringLength, "z")
    Do $$$AssertEquals($Length(tAtCeiling), 3641144, "the string ceiling is 3,641,144 -- the figure the skills quote")

    Set tMsg = ##class(Example.MSG.MaxLenBoundaries).%New()
    Set tMsg.Unlimited = tAtCeiling

    // The validator is satisfied: the value IS a legal string for a MAXLEN="" property.
    Do $$$AssertStatusOK(tMsg.%ValidateObject())

    // The saver is not. #5002 wrapping <MAXSTRING>, raised inside generated %SaveData code -- so the
    // error names a routine, not the property, which is what makes it hard to diagnose.
    Set tSC = tMsg.%Save()
    Do $$$AssertStatusNotOK(tSC)
    Do $$$AssertEquals($System.Status.GetErrorCodes(tSC), 5002, "at the ceiling the failure is #5002, not the #7201 a length error usually gives")
}

}
