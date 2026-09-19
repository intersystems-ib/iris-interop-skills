# Headless probes — running what `iris_execute` cannot

The two mechanics behind "resolve real names with a tool, never from memory": the headless bootstrap for calls `iris_execute` refuses, and how a `[SqlProc]` is actually addressed from SQL. Read this when a lookup or a probe will not run, not before.

## Contents

- Headless bootstrap — running the calls `iris_execute` cannot
- Calling a `[SqlProc]` — the name is not the class name

### Headless bootstrap — running the calls `iris_execute` cannot

Some setup APIs do not survive `iris_execute`. The symptom is never an error: the call reports
success, returns nothing, and the artefact you asked for is absent or half-made. **Wrap the call in a
`[SqlProc]` class method and invoke it with `SELECT`** — that is the canonical headless path, and it
is the same pattern whatever the API. Three independent failure modes converge on it:

| Failure mode | What you see | Where it bites |
|---|---|---|
| **Class-generating calls are no-ops.** `iris_execute`'s CodeMode does not run an objectgenerator. | Call succeeds, no class generated. A later compile is green, and the method is missing at *runtime*: `<METHOD DOES NOT EXIST>GetObject`. | `EnsLib.RecordMap.Generator.GenerateObject` |
| **Only device output comes back.** In HTTP CodeMode a `Quit`/`Return` value is not captured — only what you `Write` to the current device. | "Success" with an empty result; the `%Status` you returned is lost, so a failure is indistinguishable from a success. | any call whose answer is a return value |
| **`&sql` breaks `SQLCODE`.** The MCP rewrites `&sql(...)` into a `%SQL.Statement` and binds status to a generated local, never to bare `SQLCODE`. | `<UNDEFINED>` on `If SQLCODE<0` — *after* the write already succeeded, so it reads like a failed insert and invites you to retry a load that worked. (intersystems-ib/iris-interop-dev#145) | direct SQL against `Ens_Util.LookupTable` etc. |

The `[IIS-SILENT]` guard fires on the second one automatically, but it can only speak *after* the
call — recognise the shape and start from the SqlProc instead.

The skeleton, identical for every case — take a parameter, return a **string** that says what
happened, never a bare `%Status`:

```objectscript
/// Host class for headless bootstrap procedures. Shown WITH its class wrapper deliberately: as a
/// bare `ClassMethod` this snippet had no compilation unit, so no tier could compile it and the
/// one thing a reader most needs to get right — the `[SqlProc]` keyword surviving a real compile —
/// was gated by nothing.
Class MyApp.Bootstrap Extends %RegisteredObject
{

/// The shape is identical for every API in the table below: take a parameter, and return a
/// **string** that says what happened — never a bare `%Status`. In HTTP CodeMode a returned status
/// is not captured, so a failure is indistinguishable from a success.
/// Invoke via: SELECT MyApp.Bootstrap_GenerateRecordMap('MyApp.RecordMap.Censo')
ClassMethod GenerateRecordMap(pMap As %String = "") As %String [ SqlProc ]
{
    // the object-generator call iris_execute would silently swallow
    Set sc = ##class(EnsLib.RecordMap.Generator).GenerateObject(pMap)
    Quit $Select($$$ISOK(sc): "ok", 1: "FAIL: " _ $system.Status.GetErrorText(sc))
}

}
```

**Idempotency is the shared caveat.** These APIs are create-only: re-running one after editing the
source fails or silently keeps the stale artefact. Delete first, then regenerate — and put the
delete in its own SqlProc so the pair is repeatable.

| API | What it makes | Re-run behaviour |
|---|---|---|
| `EnsLib.RecordMap.Generator.GenerateObject(map)` | the `.Record` class + the `GetObject`/`PutObject` bodies | `#5768 Class already exists` — delete the `.Record` first (`business-services`) |
| `EnsLib.HL7.SchemaXML.Import(file, .cat)` | a custom HL7 schema category | overwrites, but a renamed/removed segment lingers — remove the category first (`hl7-schemas`) |
| direct SQL into `Ens_Util.LookupTable` | lookup-table rows | make it idempotent with a `DELETE WHERE TableName=…` inside the same transaction (`lookup-tables`) |

**Whatever the SqlProc generated in the namespace still has to reach disk.** These artefacts are the
documented exception to write-file-first: generate → `iris_doc(mode=get)` → `Write` to `src/`. A
`.Record` that exists only in the namespace is a CR-12 finding like any other.

### Calling a `[SqlProc]` — the name is not the class name

A `[SqlProc]` class method projects as **`<package, dots→underscores>.<Class>_<Method>`**: everything
up to the *last* dot becomes the SQL schema, then the final class name and the method name join with
an underscore. Measured against `INFORMATION_SCHEMA.ROUTINES` on IRIS 2026.1:

| class :: method | schema | function | call as |
|---|---|---|---|
| `Demo.Bootstrap` :: `Ping` | `Demo` | `Bootstrap_Ping` | `SELECT Demo.Bootstrap_Ping(…)` |
| `ImgLink.HL7.SchemaImport` :: `ImportSchema` | `ImgLink_HL7` | `SchemaImport_ImportSchema` | `SELECT ImgLink_HL7.SchemaImport_ImportSchema(…)` |

The three forms that feel right and are not:

```sql
SELECT Demo_Bootstrap_Ping('x')        -- -359 'SQLUSER.DEMO_BOOTSTRAP_PING' does not exist
SELECT Demo.Bootstrap.Ping('x')        -- -359 'DEMO.BOOTSTRAP.PING' does not exist
SELECT Demo.UTL.Bootstrap_ImportSchema()
                                       -- -359 'DEMO.UTL.BOOTSTRAP_IMPORTSCHEMA' does not exist
                                       -- The WHOLE package goes to underscores, not just the tail.
                                       -- Class Demo.UTL.Bootstrap -> schema Demo_UTL, never Demo.UTL.
                                       -- Correct: SELECT Demo_UTL.Bootstrap_ImportSchema()
```

All-underscores carries no schema qualifier at all, so IRIS resolves it against the default schema
`SQLUSER` and never finds it. The **third** is what a half-read of the rule produces: the underscore
gets applied to `Class_Method` but not to the package. A SQL function reference in IRIS carries at
most one dot, so **two or more dots in the name is always this mistake** — compare the
`ImgLink_HL7.SchemaImport_ImportSchema` row above, the same three-segment package spelled right.

Don't derive the name — read it:

```sql
SELECT ROUTINE_SCHEMA, ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME LIKE 'Bootstrap%'
SELECT parent, Name FROM %Dictionary.CompiledMethod WHERE SqlProc = 1 AND parent %STARTSWITH 'MyApp'
```

**`-149 <PRIVATE METHOD>` is a different failure and does not look like one.** It means the name
resolved but the method has no `[SqlProc]` keyword — the fix is on the class, not in the query.

SQL-BO worked flow (child-table projections, invented system catalogs): see `business-operations`
(section "Resolve real table names BEFORE the first query").

