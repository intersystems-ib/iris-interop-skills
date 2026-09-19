# REST spec-first — `%REST.Spec`, and the two routes that fail in opposite ways

Spec-first is the third way to take REST into a production, alongside the adapter's own port and a
hand-written `%CSP.REST` dispatcher (both in [rest-csp.md](rest-csp.md)). You author **one** class
holding a Swagger 2.0 document; IRIS generates the other two.

Everything below was measured on IRIS for Health 2026.1.

## Contents

- Three classes, one of them yours
- The two routes fail in OPPOSITE ways
- A failed regeneration leaves the old dispatcher serving
- What the generated dispatcher actually validates
- Where an auth guard has to live
- Publishing it, and the naming exemption

## Three classes, one of them yours

```
Pkg.REST.spec   you author it   Extends %REST.Spec, holds XData OpenAPI
Pkg.REST.disp   GENERATED       Extends %CSP.REST — the dispatcher, the web app points here
Pkg.REST.impl   GENERATED ONCE  Extends %REST.Impl — your method bodies go here
```

`.impl` is the only generated class you edit, and edits to it **survive** regeneration. `.disp` is
rewritten every time, so nothing you put there lasts.

The spec's parameters are projected into the `.impl` signature: a `get` with query parameters `n`
(integer) and `kind` (string) generates `ClassMethod Ping(n As %Integer, kind As %String)`.

## The two routes fail in OPPOSITE ways

Same mistake — an OpenAPI **3.0** document where Swagger **2.0** is required — and the two ways of
driving the generator disagree completely about it:

| route | Swagger 2.0 | OpenAPI 3.0 |
|---|---|---|
| compile the hand-authored `.spec` class | generates `.disp` + `.impl` | **compiles CLEAN, generates NOTHING, no error** |
| `##class(%REST.API).CreateApplication(name, dynObj, .err)` | `$$$OK`, generates all three | `ERROR #8738: Correct OpenAPI 2.0 version was not specified: . <$.swagger>` then `#5490` / `#5030` |

**The route you reach for by hand is the one that fails silently.** Writing the spec class and
compiling it is the obvious move, and a 3.0 document there produces a clean compile with no
dispatcher and no diagnostic — the endpoint simply 404s later. `CreateApplication` names the problem
and the JSON path (`<$.swagger>`) exactly.

So: **`swagger: "2.0"` is mandatory**, and if a spec compiles clean, check that `.disp` and `.impl`
actually exist before believing it worked.

## A failed regeneration leaves the old dispatcher serving

Measured: generate from a valid 2.0 document, then re-run `CreateApplication` on the **same
application name** with a 3.0 document. The call errors — and the previously generated `.disp` and
`.impl` are **still there and still live**. The endpoint keeps answering with the old contract.

A failed spec update is therefore not a no-op you can ignore. Either the regeneration succeeded or
your API is serving the previous version; the error alone does not tell you which.

## What the generated dispatcher actually validates

Read out of the generated `.disp` routine, not inferred. For a `required` integer with
`minimum: 1, maximum: 10`, and a string with `enum: ["a","b"]`:

| spec keyword | enforced? | what the generator emits |
|---|---|---|
| `required: true` | **yes** | `If '$data(%request.Data("n",1)) Do ##class(%REST.Impl).%ReportRESTError(..#HTTP400BADREQUEST, …)` |
| a duplicate occurrence of the parameter | **yes** | `If $data(%request.Data("n",2)) { … }` |
| `minimum` / `maximum` | **no** | nothing |
| `pattern` | **no** | nothing |
| `enum` | **no** | nothing |

There is **no `%ValidateObject` call and no validation helper anywhere in the generated dispatcher** —
only those two `$data` tests per parameter. And the projected `.impl` signature is a bare
`%Integer` / `%String` with no `MINVAL`, `MAXVAL` or `VALUELIST`, so nothing downstream catches it
either.

**So `required` and duplicate-detection are contract; `minimum`, `maximum`, `pattern` and `enum` are
documentation.** They belong in the spec because they are published to consumers — but validate them
yourself in `.impl` if the value matters. A range in the spec that nothing checks is worse than no
range, because the spec says it is guaranteed.

## Where an auth guard has to live

`%REST.Impl` has **52 methods and `OnPreHTTP` is not one of them** — it extends
`%Library.RegisteredObject`, not `%CSP.REST`. `OnPreHTTP` comes from `%CSP.Login` via `%CSP.REST`,
which is what `.disp` extends.

So a per-request guard cannot go in `.impl`. Subclass the **generated dispatcher** and point the web
application at your subclass:

```
Class Pkg.REST.Guard Extends Pkg.REST.disp
{
ClassMethod OnPreHTTP() As %Boolean { /* … */ Quit 1 }
}
```

Guarding `.disp` itself does not survive: it is regenerated.

## Publishing it, and the naming exemption

The web application's **`DispatchClass` is the `.disp` class** (or your guard subclass), never
`.impl`. `AutheEnabled = 32` is password authentication — see `rest-csp.md` for the bit table and
the endpoint permissions the service user needs.

**`Pkg.REST.spec` / `.disp` / `.impl` are exempt from CR-9.** The `Tipo` set in `interop`'s table is
`.BS/.BP/.BO/.DT/.DTS/.MSG/.RUL/.DAT/.ADP/.UTL/.HL7`, and `REST` is not in it — but two of the three
names are chosen by the generator, not by you. Do not flag them, and do not rename them: the web
application, the generator and `CreateApplication` all address them by that exact shape.
