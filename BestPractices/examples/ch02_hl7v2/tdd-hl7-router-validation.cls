/// Rule: BestPractices_Interop_IRIS.md §2.10 "HL7 file intake — the prebuilt HL7 service and the HL7-SPECIFIC router"
/// Validity: Verified against IRIS for Health 2026.1 — RUN against a live production, both directions.
/// Severity: High (case 1 alone passes against a router that validates nothing).
///
/// Pattern: the two-direction router test. A valid message must reach the normal target AND a
/// malformed one must reach the BadMessageHandler. Asserting only the first is the plugin's
/// signature defect appearing in its own test layer: it passes against a router with validation
/// switched off, because a valid message routes fine either way.
///
/// THIS IS THE ONE BANK TEST THAT NEEDS A RUNNING PRODUCTION, and it does not override
/// TestControl for that reason. Every other test here neutralises the lifecycle because its
/// subject is a class; routing is not a class, it is a behaviour of a started production, and
/// there is no way to observe it without one.
///
/// HOW A MESSAGE GETS IN, since the obvious route does not work. `EnsLib.HL7.Service.FileService`
/// cannot be driven by hand: measured, `svc.ProcessInput(aGlobalStream)` fails with
///   <PROPERTY DOES NOT EXIST> OnProcessInput+1^EnsLib.HL7.Service.FileService.1 *Filename
/// because it reads `pInput.Filename` and therefore needs a FILE-backed stream. Inject at the
/// router instead, which is where the behaviour under test lives:
///     ##class(EnsLib.Testing.Service).SendTestRequest("Router.Adt", doc, .resp, .sessionId)
/// That needs `TestingEnabled="true"` on the production, which §2.10's production sets.
///
/// THE FIXTURE MUST SET DocType, AND GETTING THIS WRONG INVERTS THE WHOLE RESULT. Measured while
/// building this test: with `ImportFromString` alone — which leaves DocType EMPTY (§2.11) — ALL
/// THREE messages, the valid one included, routed to the BadMessageHandler. No docCategory/docName
/// to match, so no rule fires and validation rejects everything. A test written that way would
/// "prove" validation works while actually proving the fixture was broken.
///
/// MEASURED, with DocType assigned, by reading Ens.MessageHeader per session:
///   valid ADT^A01           Router.Adt -> BO.AdtOut   and NO Ens.Alert hop
///   unknown type XYZ^Q99    Router.Adt -> BO.AdtBad   + Ens.Alert
///   ADT^A01 missing PID     Router.Adt -> BO.AdtBad   + Ens.Alert
/// The absence of the alert on the valid path is what proves the alert belongs to
/// AlertOnBadMessage and is not just the outbound file write failing.
///
/// AND THE TARGET IS THE ASSERTION, NOT THE STATUS. The message Status differs with timing and
/// with whether the outbound directory exists; the TargetConfigName does not. Until v1.25.0 this
/// production's BadMessageHandler was `BO.AdtOut` — the same item the rule sends valid messages to
/// — so both directions converged and no assertion could have distinguished them. Tier-1 C11 now
/// refuses that collision.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.Hl7RouterValidation", namespace="<NS>")
Class Example.Tests.Hl7RouterValidation Extends %UnitTest.TestProduction
{

/// The framework starts and stops this production. TestControl is deliberately NOT overridden.
Parameter PRODUCTION = "Example.Productions.Hl7Intake";

/// Build an HL7 message and give it a DocType. Omitting DocTypeSet inverts every result below.
ClassMethod Fixture(pKind As %String, Output pDoc As EnsLib.HL7.Message) As %Status [ Private ]
{
    Set tCR = $Char(13)
    If pKind = "valid" {
        Set tText = "MSH|^~\&|S|F|R|F|20260101120000||ADT^A01^ADT_A01|G1|P|2.5" _ tCR
        Set tText = tText _ "EVN|A01|20260101120000" _ tCR
        Set tText = tText _ "PID|1||12345^^^MRN||DOE^JOHN" _ tCR
        Set tText = tText _ "PV1|1|I|W^1^A" _ tCR
    } ElseIf pKind = "unknowntype" {
        Set tText = "MSH|^~\&|S|F|R|F|20260101120000||XYZ^Q99^XYZ_Q99|B1|P|2.5" _ tCR
        Set tText = tText _ "PID|1||1^^^MRN||X^Y" _ tCR
    } Else {
        Set tText = "MSH|^~\&|S|F|R|F|20260101120000||ADT^A01^ADT_A01|B2|P|2.5" _ tCR
        Set tText = tText _ "ZZZ|bogus" _ tCR
    }

    Set pDoc = ##class(EnsLib.HL7.Message).ImportFromString(tText, .tSC)
    Quit:$$$ISERR(tSC) tSC
    Quit:'$IsObject(pDoc) tSC
    Do pDoc.DocTypeSet("2.5:ADT_A01")
    Quit pDoc.%Save()
}

/// Send one message to the router and return the target it was routed to.
ClassMethod RouteOf(pKind As %String, Output pSawAlert As %Boolean) As %String [ Private ]
{
    Set pSawAlert = 0
    Set tTarget = ""
    Quit:$$$ISERR(..Fixture(pKind, .tDoc)) ""

    Set tSC = ##class(EnsLib.Testing.Service).SendTestRequest("Router.Adt", tDoc, .tResp, .tSession)
    Quit:$$$ISERR(tSC) ""
    Hang 3

    Set tSQL = "SELECT TargetConfigName FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'Router.Adt'"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, tSession)
    While tRS.%Next() {
        Set tName = tRS.%Get("TargetConfigName")
        If tName = "Ens.Alert" {
            Set pSawAlert = 1
        } ElseIf $Extract(tName, 1, 3) = "BO." {
            Set tTarget = tName
        }
    }
    Quit tTarget
}

/// Direction 1: a valid message reaches the normal target, and raises no bad-message alert.
Method TestValidMessageReachesTarget()
{
    Set tTarget = ..RouteOf("valid", .tAlert)
    Do $$$AssertEquals(tTarget, "BO.AdtOut", "a valid ADT must route to the normal target")
    Do $$$AssertEquals(tAlert, 0, "a valid message must NOT raise a bad-message alert")
}

/// Direction 2 — the half that a one-sided test omits, and the reason this file exists. An
/// unknown message type must reach the BadMessageHandler, not the normal target.
Method TestUnknownTypeReachesBadHandler()
{
    Set tTarget = ..RouteOf("unknowntype", .tAlert)
    Do $$$AssertEquals(tTarget, "BO.AdtBad", "an unknown message type must reach the BadMessageHandler")
    Do $$$AssertEquals(tAlert, 1, "and AlertOnBadMessage must fire")
}

/// Direction 2, second shape: the right type carrying the wrong structure.
Method TestMalformedStructureReachesBadHandler()
{
    Set tTarget = ..RouteOf("badstruct", .tAlert)
    Do $$$AssertEquals(tTarget, "BO.AdtBad", "a malformed ADT must reach the BadMessageHandler")
    Do $$$AssertEquals(tAlert, 1, "and AlertOnBadMessage must fire")
}

/// The control that makes the two directions meaningful: the two targets must be DIFFERENT items.
/// If BadMessageHandler equals the rule's target, both tests above pass trivially and validation
/// is unobservable — which is exactly how this production shipped until v1.25.0.
Method TestTargetsAreDistinguishable()
{
    Set tGood = ..RouteOf("valid", .tA)
    Set tBad = ..RouteOf("unknowntype", .tB)
    Do $$$AssertNotEquals(tGood, tBad, "control: the good and bad paths must end at different items")
}

}
