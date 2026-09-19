# Authoring a Search Table

How to author a Search Table class and wire it. This is a build task, not a search task — read it when you need a new one, not when you are looking for a message.

### Authoring a Search Table

Everything above assumes someone already declared the fields. Authoring one is a single subclass
plus one production setting:

```objectscript
Class MyApp.Search.Hl7Adt Extends EnsLib.HL7.SearchTable
{
XData SearchSpec [ XMLNamespace = "http://www.intersystems.com/EnsSearchTable" ]
{
<Items>
  <Item DocType="" PropName="PatientFirstName">[PID:5().2]</Item>
</Items>
}
}
```

- **The XData namespace is `EnsSearchTable`** — literally
  `http://www.intersystems.com/EnsSearchTable`. `EnsHL7SearchTable`, the form you'd guess by
  analogy with the class name, does not work.
- **`PropType`**: the only values observed in a live catalogue
  (`Ens_Config.SearchTableProp.PropType` on a namespace carrying 257 real search-table rows) are
  `String:CaseSensitive` and `String:CaseInsensitive`. Both `PropType="String"` and
  `PropType="String:25"` fail with `ErrDatatypeValidationFailed`. **Omitting the attribute
  entirely also works and is the safe default.** (`DateTime` / `Numeric` are unverified against
  that catalogue — don't reach for them without checking.)
- **A search table indexes nothing until it is assigned** — and only messages received from that
  point on are indexed. Nothing back-indexes existing messages (same caveat as in the query section
  above).

#### Assigning it — `SearchTableClass` is a `Host` setting on the service and the operation

This is the step that is easy to read past, because the class compiles happily without it and the
search table simply stays empty. `SearchTableClass` is declared on `EnsLib.HL7.Service.Standard`
and `EnsLib.HL7.Operation.Standard`, so **every** HL7 service and operation carries it, always with
`Target="Host"`:

```xml
<Item Name="BS.AdtIn" ClassName="EnsLib.HL7.Service.FileService" Enabled="true">
  <Setting Target="Adapter" Name="FilePath">/data/hl7in</Setting>
  <Setting Target="Host"    Name="MessageSchemaCategory">2.5</Setting>
  <Setting Target="Host"    Name="SearchTableClass">MyApp.Search.Hl7Adt</Setting>
  <Setting Target="Host"    Name="TargetConfigNames">BO.AdtOut</Setting>
</Item>
```

Or on a running production, without editing the class:

```
iris_production_item(action="set_settings", item="BS.AdtIn", production="MyApp.Production",
                     settings={"SearchTableClass": "MyApp.Search.Hl7Adt"}, namespace="APP")
```

(That changes the namespace only — pull the production class back to `src/` afterwards, see
`production-lifecycle`.)

**Routers do not carry `SearchTableClass`.** `EnsLib.HL7.MsgRouter.RoutingEngine` has no such
property, so assigning it there is not an option you have missed — index at the **service** (and/or
the operation) instead. The one exception is `EnsLib.MsgRouter.RoutingEngineST`, a routing engine
whose whole purpose is to carry one.

Once compiled and assigned, the rows land in the shared base extent `EnsLib_HL7.SearchTable` and
are queried by `PropId` exactly as shown in Join 2 — the subclass never gets a table of its own.
Verified end to end: an `ADT_A01` through a `FileService` with the above settings produced six rows
for one message — four built-in (`MSHControlID`, `MSHTypeName`, `PatientID`, `PatientName`) and two
from the custom subclass, the latter carrying
`ClassDerivation = MyApp.Search.Hl7Adt~EnsLib.HL7.SearchTable`. A built-in prop whose field is empty
in the message simply gets no row (`PatientAcct` was absent because PID-18 was).

#### `PropValue` is stored LOWERCASED under the default `PropType`

The default (and the `String:CaseInsensitive` setting) normalises on the way in. Measured on the
message above:

| Message field | Stored `PropValue` |
|---|---|
| `ADT^A01` | `adt_a01` |
| `GARCIA^MARIA` | `garcia^maria` |
| `HOUSE` | `house` |
| `I` | `i` |

So `WHERE st.PropValue = 'GARCIA^MARIA'` returns **nothing** and reads as "that patient was never
here". Lowercase the literal, or use `%STARTSWITH`/`LIKE` against a lowercased pattern. The
`PatientID` example in Join 2 dodges this only because it is numeric.

