# Canonical test skeletons

One skeleton per thing under test — a DTL, HL7 fixtures, a routing rule, a BO method, a BPL via the Testing Service — plus enabling the Testing Service on a production. Read the one that matches what you are testing.

## Contents

- Canonical skeletons (USE THESE AS TEMPLATES)
- DTL test
- HL7 test fixtures — the classmethod, never the instance method
- Routing rule test (integration style — preferred)
- BO method test (integration with real adapter)
- BPL via Testing Service
- Enabling the Testing Service on a production

## Canonical skeletons (USE THESE AS TEMPLATES)

### DTL test

```objectscript
Class MyApp.Tests.DT.Censo2Menus Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }   // production managed externally

/// Verifies that Apellido1 + Apellido2 are concatenated with a single space separator
Method TestApellidosConcat()
{
    Set src = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set src.Apellido1 = "Pérez"
    Set src.Apellido2 = "López"
    Set src.Nombre = "Carlos"  Set src.Dieta = "Basal"  Set src.FechaNacimiento = "01/01/1970"
    Set tSC = ##class(MyApp.DT.Censo2Menus).Transform(src, .tgt)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tgt.Apellidos, "Pérez López", "Apellidos with single space")
}

/// Verifies that an invalid date (32/13/1990) is rejected with an error status
Method TestFechaInvalidaSeAisla()
{
    Set src = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set src.FechaNacimiento = "32/13/1990"
    Set src.Nombre = "X"  Set src.Apellido1 = "Y"  Set src.Dieta = "Basal"
    Set tSC = ##class(MyApp.DT.Censo2Menus).Transform(src, .tgt)
    Do $$$AssertStatusNotOK(tSC, "Bad date must error out")
}

}
```

Run: `do ##class(MyApp.Tests.DT.Censo2Menus).Run()`.

### HL7 test fixtures — the classmethod, never the instance method

`EnsLib.HL7.Message` has two import paths and they do **not** do the same thing:

| Form | Behaviour |
|---|---|
| `msg.ImportFromString(raw)` — **instance** method | Parses the **first segment only**. Every other segment is dropped. No error, no warning. |
| `##class(EnsLib.HL7.Message).ImportFromString(raw, .sc)` — **classmethod** | Parses the full multi-segment message and returns the populated object. |

The instance form is the dangerous one precisely because it does not fail: the fixture ends up
holding only MSH, every assertion on PID/PV1/AL1/ZDI reads `""`, `<if>` defaults interpret the
empty string as "use the default", and the test goes **green while testing nothing**. This is the
`AL1Count` failure mode in a different costume — see `transformations`.

```objectscript
/// Segments are separated by $Char(13) — CR, the HL7 segment terminator. Not $Char(10), not CRLF.
Set raw = "MSH|^~\&|HIS|HOSP||HOSP|20260513||ADT^A01|001|P|2.5" _ $Char(13) _
          "EVN|A01|20260513" _ $Char(13) _
          "PID|1||HL7-1001^^^HOSP^MR||Perez^Juan^^^^^L||19620315|M" _ $Char(13) _
          "PV1|1|I|3^301A^E1" _ $Char(13) _
          "AL1|1|FA|LCT^Lactosa^L" _ $Char(13) _
          "ZDI|1|Basal|Sin observaciones"

// CLASSMETHOD form — returns the populated message, and `sc` is the only thing that tells you
Set msg = ##class(EnsLib.HL7.Message).ImportFromString(raw, .sc)
Do $$$AssertStatusOK(sc)

// DocType goes on AFTER the import. ImportFromString resets the parse state, so assigning it
// first has no effect at all.
Set msg.DocType = "MySchema:ADT_A01"
```

Assert on a segment beyond MSH in every HL7 fixture — `$$$AssertEquals(msg.GetValueAt("PID:3.1"), …)`
— so that a fixture that silently collapsed to one segment fails the test instead of passing it.

Remember that parsing a message is **not** a test of a custom schema's structure: see the Custom
HL7 schema row in the decision table above.

### Routing rule test (integration style — preferred)

```objectscript
Class MyApp.Tests.Rule.RoutingCenso Extends MyApp.Tests.Base
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    // ##super() FIRST: the base allocates this run's RunId here. Skip it and ..Key()
    // silently returns "TST--<tag>" for every test, colliding with every other run that did
    // the same -- the failure this whole section exists to prevent.
    Set tSC = ##super()
    Quit:$$$ISERR(tSC) tSC
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

/// Verifies that the Router.Censo dispatches a census record to BO.Cocina
Method TestRouterDispatchaACocina()
{
    Set rec = ##class(MyApp.RecordMap.Censo.Record).%New()
    Set tKey = ..Key("RULE-1")   ; one value, used by the insert AND the assert below
    Set rec.ID = tKey
    ; ... fill the rest of the record fields ...
    Do $$$AssertStatusOK(rec.%Save())

    Set baseId = ..LastLogId
    Do $$$AssertStatusOK(..SendRequest("Router.Censo", rec, .resp, 0))
    Hang 2  ; async settle

    Kill Log
    Do ..GetEventLog("info", "BO.Cocina", baseId, .Log, .new)
    Set tFound = 0
    For i=1:1:$G(Log) { If Log(i,"Text") [ tKey Set tFound = 1 Quit }
    Do $$$AssertTrue(tFound, tKey _ " dispatched to BO.Cocina")
}

}
```

### BO method test (integration with real adapter)

> **Prerequisite — `..SendRequest` needs the Testing Service turned on.** Both skeletons below
> dispatch through `EnsLib.Testing.Service`, which is not available by default. Set
> `TestingEnabled="true"` on the production (see §"Enabling the Testing Service" below) **before**
> the first run, or the very first `..SendRequest` fails with
> `<Ens>ErrBusinessDispatchNameNotRegistered` — an error that names `EnsLib.Testing.Service` and so
> sends you looking for a missing config item rather than a missing flag.


```objectscript
Class MyApp.Tests.BO.Menus2Cocina Extends MyApp.Tests.Base
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    // ##super() FIRST: the base allocates this run's RunId here. Skip it and ..Key()
    // silently returns "TST--<tag>" for every test, colliding with every other run that did
    // the same -- the failure this whole section exists to prevent.
    Set tSC = ##super()
    Quit:$$$ISERR(tSC) tSC
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

Method ExpectInsertLogged(pBaseId, pPacienteId, pDesc)
{
    Kill Log
    Do ..GetEventLog("info", "BO.Cocina", pBaseId, .Log, .new)
    Set tFound = 0
    For i=1:1:$G(Log) {
        If Log(i,"Text") [ ("INSERT OK paciente_id="_pPacienteId) Set tFound = 1 Quit
    }
    Do $$$AssertTrue(tFound, pDesc)
}

/// Verifies that empty Alergias ("") is marshalled correctly to SQL NULL by the JDBC adapter
Method TestEmptyAlergiasToNull()
{
    ; Catches marshalling bugs that no stub would: does the real JDBC driver
    ; translate "" to SQL NULL, or to empty string?
    Set req = ##class(MyApp.MSG.MenuRequest).%New()
    Set tKey = ..Key("EMPTY")
    Set req.PacienteId = tKey
    Set req.Nombre = "X"  Set req.Apellidos = "Y"  Set req.TipoDieta = "Basal"
    Set req.Alergias = ""
    Do $$$AssertStatusOK(req.%Save())

    Set baseId = ..LastLogId
    Do $$$AssertStatusOK(..SendRequest("BO.Cocina", req, .resp, 0))
    Hang 2

    Do ..ExpectInsertLogged(baseId, tKey, "INSERT OK logged for " _ tKey)
}

/// Clean up exactly THIS run's rows. The DELETE names a table, so it lives in the suite that owns
/// that table -- not in the shared base every suite inherits. Scoped by this run's prefix, so it
/// cannot take another run's data even if two runs overlap.
Method OnAfterAllTests() As %Status
{
    Set tPattern = "TST-" _ ..RunId _ "-%"
    &sql(DELETE FROM Cocina.Menus WHERE paciente_id LIKE :tPattern)
    Quit $$$OK
}

}
```

### BPL via Testing Service

> **`$IsObject(resp)` is not evidence the process worked.** A BPL with a `<catchall>` that records a
> fault and does not propagate it completes at Status 9 **Completed** and returns a populated response
> object — so `$$$AssertStatusOK(..SendRequest(...))` and `$$$AssertEquals($IsObject(resp), 1)` both
> pass on a run where every `<call>` failed. Measured: deliverable §5.23. Assert returned field
> **values**, plus `Ens_Util.Log` rows of `Type = 2` (Error), or the target's `Ens.MessageHeader.Status`.

```objectscript
Class MyApp.Tests.BPL.MyProcess Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "MyApp.Production";

Method TestControl() As %Status { Quit $$$OK }

Method OnBeforeAllTests() As %Status
{
    &sql(SELECT NVL(MAX(ID),0) INTO :tMax FROM Ens_Util.Log)
    Set ..BaseLogId = tMax + 1, ..LastLogId = ..BaseLogId
    Quit $$$OK
}

/// Verifies that BP.MyProcess actually DID the work — not merely that it replied.
Method TestProcessReceivesAndForwards()
{
    Set req = ##class(MyApp.MSG.SomeRequest).%New()
    Set req.Field = "value"
    Do $$$AssertStatusOK(..SendRequest("BP.MyProcess", req, .resp, 1, 30))
    ; SendRequest with GetReply=1 waits for the response. Resp is now populated.
    Do $$$AssertEquals($IsObject(resp), 1, "Got a response back")
    ; NEITHER ASSERTION ABOVE IS SUFFICIENT. A BPL whose <catchall> records a fault without
    ; propagating it completes at Status 9 and returns a real response object, so both pass while
    ; every <call> failed — measured, deliverable §5.23. Assert the VALUE, and assert the log.
    Do $$$AssertEquals(resp.Field, "expected value", "the response carries the transformed value")
    ; The host variable must be a LOCAL. Measured: `:..BaseLogId` fails to compile with
    ; "Host variable name must begin with either % or a letter, not '.'" — copy the property out first.
    Set tBase = ..BaseLogId
    &sql(SELECT COUNT(*) INTO :tErrors FROM Ens_Util.Log WHERE ID >= :tBase AND Type = 2)
    Do $$$AssertEquals(tErrors, 0, "and nothing in this run logged an Error (Ens.DataType.LogType 2)")
}

}
```

## Enabling the Testing Service on a production

Add `TestingEnabled="true"` to the `<Production>` opening tag in the `XData ProductionDefinition`:

```xml
XData ProductionDefinition
{
<Production Name="MyApp.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  ...
</Production>
}
```

Effect:
- The IRIS Management Portal exposes a "Testing Service" page (under Interoperability) for manual dispatch of test messages to any BP or BO. Requires `%Ens_TestingService:USE` resource.
- Programmatic: `..SendRequest(...)` and `EnsLib.Testing.Service.SendTestRequest(...)` both work when the production is running with this flag.
- Internally: a hidden `EnsLib.Testing.Process` is registered and dispatches the wrapped `EnsLib.Testing.Request` to the target via `SendRequestAsync`.

**The flag is sufficient — you do not add `EnsLib.Testing.*` config items.** Measured on IRIS for
Health 2026.1, sending to an adapterless BO:

| Production configuration | `SendTestRequest(..., getReply=1)` |
|---|---|
| `TestingEnabled="true"`, **no** Testing items | **works** — session created, response returned |
| neither the flag nor any item | `ErrBusinessDispatchNameNotRegistered: 'EnsLib.Testing.Service'` |
| `EnsLib.Testing.Service` item only, no flag | `ErrBusinessDispatchNameNotRegistered: 'EnsLib.Testing.Process'` |
| **both** `EnsLib.Testing.Service` *and* `EnsLib.Testing.Process` items, no flag | works |

So there are two routes, and the flag is the one to use — one attribute instead of two config items
that then ship in your production definition.

**Read the error as "the flag is missing", not "an item is missing".** Both failures above name a
*class* as an unregistered dispatch name, which reads like a missing config item and invites you to
add one. Adding `EnsLib.Testing.Service` alone then produces the second error — for **asynchronous**
sends as well as synchronous ones, since the wrapped request goes through `EnsLib.Testing.Process`
either way — and two rounds of that look like a config rabbit hole rather than a one-attribute fix.

If you genuinely cannot set the flag (a production you do not own, or one under deploy-to-prod
automation that strips it), the explicit-items route is the fallback, and you need **both**.

**Important — security**: `TestingEnabled="true"` is a development setting — the **correct default** in dev/workshop productions, and a risk only where deploy-to-prod automation exists. **Never deploy a production to prod with this flag on** — anyone with the Testing resource can fabricate messages into running BPs/BOs. Strip it (or guard via a deployment-time setting) before promoting.

