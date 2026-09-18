/// Rule: BestPractices_Interop_IRIS.md §5.18 "A %UnitTest lifecycle callback that is misspelled or mis-signatured is simply never invoked"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (cleanup that never runs makes the NEXT run assert against stale rows and pass).
///
/// Pattern: the `%UnitTest` fixture-lifecycle and event-log reader, folded into one class because the
/// coverage map's two rows (S27, S28) are the same subject seen from two ends: what a test run sets
/// up and tears down, and what it is allowed to conclude from the log afterwards.
///
/// THE CALLBACKS, exactly. All four are instance `Method`s returning `%Status`:
///
///     OnBeforeAllTests()              no arguments
///     OnAfterAllTests()               no arguments
///     OnBeforeOneTest(testname)       ONE argument
///     OnAfterOneTest(testname)        ONE argument
///
/// That asymmetry is the whole trap: the per-test pair takes a name and the all-tests pair takes
/// nothing, so an argument copied from one to the other looks right.
///
/// THREE WAYS TO GET IT WRONG, measured -- and only ONE of them is the silent one the coverage map
/// expected. This corrects that row, and it corrects a wrong reading of my own along the way:
///
///     declared `ClassMethod OnAfterAllTests()`    ERROR #5477 at COMPILE time:
///                                                "keyword 'ClassMethod' must be '0'"       LOUD
///     misspelled `OnBeforeAllTest()` (singular)   compiles clean, NEVER INVOKED             SILENT
///     `OnBeforeAllTests(pExtra As %String = "")`  compiles clean, and IS STILL INVOKED      harmless
///
/// The row said a misspelled "or mis-signatured" callback "compiles and is simply never invoked".
/// Half right: the misspelling is exactly that, and an extra DEFAULTED argument is not -- measured
/// with a marker global, `extra-arg ran=1 | misspelled ran=NO`.
///
/// HOW I GOT THAT WRONG FIRST, because the mistake is instructive and cheap to repeat. The initial
/// probe put the extra argument on `OnAfterAllTests` and read the marker from a test method. It
/// reported NEVER RAN -- and of course it did: `OnAfterAllTests` runs AFTER every test, so no test
/// can ever observe its marker, whatever its signature. The experiment could only ever return that
/// answer. Moving the same argument to `OnBeforeAllTests`, which runs first, shows it running.
/// A probe whose result is forced by its own ordering has measured the ordering, not the subject.
///
/// WHY THAT MATTERS MORE THAN IT SOUNDS. A cleanup that never runs does not fail the run it belongs
/// to -- it fails the NEXT one, by leaving rows behind, and it fails it in the direction of PASSING:
/// the next run's assertions find the previous run's data and are satisfied by it. That is the
/// same shape as the search-table and verdict-reader defects elsewhere in this bank: the failure
/// presents as success, one step removed from its cause.
///
/// AND S28's PREMISE WAS WRONG, which is worth recording because what replaced it is sharper. The
/// row said "every skeleton bounds its loop with `For i=1:1:$G(Log)`; if the top node is not the
/// count the body never executes". Measured -- the top node IS the count, so the skeletons are fine:
///
///     GetEventLog("all", "", 0, .Log, .new)  ->  $D(Log)=11   Log=287   new=287
///     `For i=1:1:$G(Log)` iterations         ->  287, and a $Order walk agrees
///
/// THE REAL HAZARD IS THE WINDOW, AND IT IS NOT THE ARGUMENT THAT CONTROLS IT. `GetEventLog`'s
/// `baseId` argument does not set the floor -- the EFFECTIVE FLOOR IS THE HIGHER of `baseId` and the
/// instance's `BaseLogId` property. Measured, five combinations, MAX(ID) = 287:
///
///     BaseLogId = 287   baseId = 0     ->    1 row
///     BaseLogId = 287   baseId = 1     ->    1 row      <- the ARGUMENT IS IGNORED
///     BaseLogId = 0     baseId = 0     ->  287 rows
///     BaseLogId = 0     baseId = 287   ->    1 row      <- here the argument wins
///     BaseLogId = ""    baseId = 1     ->  287 rows
///
/// So you can only ever RAISE the floor. Passing a smaller `baseId` cannot widen the window, and
/// `baseId = 0` does not mean "from the beginning" -- it means "whatever BaseLogId says".
///
/// That interacts with advice this plugin gives and is right to give. `tdd` says to seed
/// `BaseLogId` in `OnBeforeAllTests` from `MAX(ID)`, which is correct for an integration test: it
/// scopes every later read to this run. The consequence, which was nowhere written down, is that
/// every `GetEventLog` call in the suite is then permanently scoped to this run and NO argument can
/// reach back past it. A test that believes it is reading "the whole log" is reading a few rows.
///
/// WHICH IS WHY AN ABSENCE CLAIM NEEDS A NON-EMPTY WINDOW. "No error was logged" over a window of
/// zero entries passes, and nothing in the assertion says how much it examined. Establish the window
/// is non-empty first -- two lines, and `TestAbsenceOverAnEmptyWindowIsVacuous` is the negative
/// control proving the guard is load-bearing.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                        PASSED 7/7
///     OnBeforeAllTests renamed OnBeforeAllTest           TestFixtureWasSeeded                  FAILS
///     the floor asserted as the LOWER of the two         TestWindowFloorIsTheHigherOfTheTwo    FAILS
///     the empty window asserted to be non-empty          TestAbsenceOverAnEmptyWindowIsVacuous FAILS
///
/// All four versions compile, so tier 2 is green on every one of them.
///
/// TWO MUTATIONS THAT PASSED, and why neither is a gap:
///   * `OnBeforeAllTests` given an extra defaulted argument -- it still runs, so nothing should fail.
///     That is the corrected finding above, not a blind spot.
///   * DELETING the non-empty-window assertion -- removing an assertion cannot make a suite red. A
///     mutation has to change the BEHAVIOUR under test; deleting a line from the test itself only
///     makes the test weaker, and expecting red from that is the experiment pointed backwards. The
///     guard's value is shown instead by `TestAbsenceOverAnEmptyWindowIsVacuous`, which demonstrates
///     on real data that the absence assert passes over a window of zero entries.
///
/// ONE MORE THING THAT WENT WRONG WHILE WRITING THIS, kept because it is the subject biting the
/// author. The first `TestAbsenceNeedsANonEmptyWindow` asserted that a `baseId = 0` window would be
/// much LARGER than a `baseId = MAX(ID)` one. It failed, and the obvious reading was a broken guard.
/// It was not: `OnBeforeAllTests` had seeded `BaseLogId` to MAX(ID), so BOTH windows were floored
/// there and both returned one row -- the assertion asked for something the API cannot do. An
/// isolated probe with no fixture gave 287 and 1 and looked like a contradiction, which is what sent
/// me to measure the floor properly. When a test and a probe disagree, the difference between them
/// IS the finding.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.LifecycleAndEventLog", namespace="<NS>")
Class Example.Tests.LifecycleAndEventLog Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// The marker the fixture writes, so "did the callback run?" is answerable rather than assumed.
/// A global rather than a property: the framework instantiates the test case, so an instance
/// property set in OnBeforeAllTests would be visible anyway -- but a global also survives the
/// mutation experiment in the header, where the callback is renamed and must be seen NOT to run.
Parameter MARKER = "^ExampleLifecycleMarker";

/// Neutralises the production start/stop this superclass would drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Instance Method, NO arguments. Declaring it `ClassMethod` is `#5477`; adding an argument compiles
/// and is never invoked. See the header.
Method OnBeforeAllTests() As %Status
{
    // Seed the log window. `tdd` records that GetEventLog returns nothing when BaseLogId is empty;
    // this is where it gets a value, and it must be read BEFORE the tests generate any entries.
    Set tMax = 0
    &sql(SELECT MAX(ID) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = +$Get(tMax)

    Set @..#MARKER@("before") = $Get(@..#MARKER@("before")) + 1
    Set @..#MARKER@("baseLogId") = ..BaseLogId
    Quit $$$OK
}

/// The cleanup half. Everything this suite wrote goes away here, so the NEXT run starts from a known
/// state rather than inheriting this one's rows.
Method OnAfterAllTests() As %Status
{
    Set @..#MARKER@("after") = $Get(@..#MARKER@("after")) + 1
    Quit $$$OK
}

/// The fixture ran at all. Without this the suite cannot distinguish "cleanup happened" from
/// "cleanup was never invoked", which is precisely the defect the header measures.
Method TestFixtureWasSeeded()
{
    Do $$$AssertEquals($Get(@..#MARKER@("before"), 0) > 0, 1, "OnBeforeAllTests must have been invoked -- a misspelled or extra-argument version is NEVER called")
    Do $$$AssertNotEquals($Get(@..#MARKER@("baseLogId"), ""), "", "and it must have seeded BaseLogId")
    Do $$$AssertNotEquals(..BaseLogId, "", "which GetEventLog needs; empty means it returns nothing")
}

/// The top node of the GetEventLog array IS the count -- so the conventional loop bound is correct.
Method TestTopNodeIsTheCount()
{
    Kill tLog
    Do ..GetEventLog("all", "", 0, .tLog, .tNew)

    Set tWalked = 0
    Set k = ""
    For {
        Set k = $Order(tLog(k))
        Quit:k=""
        Set tWalked = tWalked + 1
    }

    Do $$$AssertEquals(+$Get(tLog), tWalked, "the top node equals the number of first-level subscripts")
    Do $$$AssertEquals(+$Get(tNew), +$Get(tLog), "and `new` agrees with it")
    Do $$$AssertEquals(tWalked > 0, 1, "control: the whole-log window is non-empty, so this comparison means something")
}

/// An absence claim, made correctly: establish the window is non-empty FIRST.
Method TestNoErrorLogged()
{
    Kill tLog
    Do ..GetEventLog("all", "", 0, .tLog, .tNew)

    // THE GUARD. The window is floored at BaseLogId, which OnBeforeAllTests seeded, so this reads
    // "since this suite started" -- a small window by design. Non-empty is what matters, not large.
    Do $$$AssertEquals(+$Get(tLog) > 0, 1, "the window must be non-empty before an absence can be claimed")

    Set tFound = 0
    For i = 1:1:$Get(tLog) {
        If $Get(tLog(i, "Text")) [ "ExampleLifecycleSentinelThatIsNeverLogged" {
            Set tFound = 1
        }
    }
    Do $$$AssertEquals(tFound, 0, "the sentinel is genuinely absent from a window we know we read")
}

/// THE FLOOR. The effective floor is the HIGHER of the argument and the property -- so the argument
/// cannot widen the window, only narrow it.
Method TestWindowFloorIsTheHigherOfTheTwo()
{
    Set tMax = 0
    &sql(SELECT MAX(ID) INTO :tMax FROM Ens_Util.Log)
    Set tSaved = ..BaseLogId

    // property at the end, argument at the beginning: the PROPERTY wins.
    Set ..BaseLogId = +tMax
    Kill a
    Do ..GetEventLog("all", "", 1, .a, .an)
    Set tPropertyWins = +$Get(a)

    // property at the beginning, argument at the end: the ARGUMENT wins.
    Set ..BaseLogId = 0
    Kill b
    Do ..GetEventLog("all", "", +tMax, .b, .bn)
    Set tArgumentWins = +$Get(b)

    // property at the beginning, argument at the beginning: the whole log.
    Set ..BaseLogId = 0
    Kill c
    Do ..GetEventLog("all", "", 0, .c, .cn)
    Set tWholeLog = +$Get(c)

    Set ..BaseLogId = tSaved

    Do $$$AssertEquals(tWholeLog > tPropertyWins, 1, "a low floor on BOTH gives a much wider window")
    Do $$$AssertEquals(tWholeLog > tArgumentWins, 1, "raising EITHER one narrows it")
    Do $$$AssertEquals(tPropertyWins < 10, 1, "BaseLogId=MAX wins over baseId=1 -- the argument cannot widen the window")
    Do $$$AssertEquals(tArgumentWins < 10, 1, "and baseId=MAX wins over BaseLogId=0")
}

/// THE NEGATIVE CONTROL for the guard in TestNoErrorLogged. Over a window that is genuinely EMPTY,
/// the same absence assert passes while examining nothing at all.
Method TestAbsenceOverAnEmptyWindowIsVacuous()
{
    Set tMax = 0
    &sql(SELECT MAX(ID) INTO :tMax FROM Ens_Util.Log)
    Set tSaved = ..BaseLogId

    // A floor past the end of the log: nothing can be in this window.
    Set ..BaseLogId = +tMax + 1000
    Kill tEmpty
    Do ..GetEventLog("all", "", 0, .tEmpty, .tNewEmpty)
    Set tCount = +$Get(tEmpty)

    Set ..BaseLogId = tSaved

    Do $$$AssertEquals(tCount, 0, "a floor past the end of the log yields an EMPTY window")

    // The absence assert over it -- it passes, having looked at nothing.
    Set tFound = 0
    For i = 1:1:tCount {
        If $Get(tEmpty(i, "Text")) [ "anything at all" {
            Set tFound = 1
        }
    }
    Do $$$AssertEquals(tFound, 0, "and 'nothing was logged' is satisfied by a window containing nothing -- which is why the guard exists")
}

/// The per-test callbacks take an argument where the all-tests pair takes none. Asserted so the
/// asymmetry is recorded somewhere executable rather than only in prose.
Method TestCallbackSignaturesAreAsymmetric()
{
    Do $$$AssertEquals(..SpecOf("OnBeforeAllTests"), "", "OnBeforeAllTests takes no arguments")
    Do $$$AssertEquals(..SpecOf("OnAfterAllTests"), "", "nor does OnAfterAllTests")
    Do $$$AssertEquals(..SpecOf("OnBeforeOneTest"), "testname:%String", "OnBeforeOneTest takes the test name")
    Do $$$AssertEquals(..SpecOf("OnAfterOneTest"), "testname:%String", "and so does OnAfterOneTest")
}

ClassMethod SpecOf(pMethod As %String) As %String [ Private ]
{
    Set tSpec = ""
    &sql(SELECT FormalSpec INTO :tSpec FROM %Dictionary.CompiledMethod
         WHERE parent = '%UnitTest.TestCase' AND Name = :pMethod)
    Quit $Select(SQLCODE '= 0: "<not found>", 1: $Get(tSpec))
}

}
