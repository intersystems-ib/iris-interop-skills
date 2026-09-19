# Failing loud on misconfiguration — `OnInit()` settings validation

A hardening pattern, not a build step: validate the settings a Business Service depends on when
the production starts it, so a missing directory or credential fails at start rather than on the
first message. Nothing in a standard file / HL7 / REST intake requires it.

## OnInit settings validation

`OnInit()` runs once when the production starts the BS. Use it to fail loud on misconfiguration —
but hand control to the base class first:

```objectscript
Method OnInit() As %Status
{
    Set tSC = ##super()                 // MANDATORY on a prebuilt EnsLib.* service
    Quit:$$$ISERR(tSC) tSC

    If ..TargetConfigNames="" Quit $$$ERROR($$$EnsErrGeneral,"TargetConfigNames is required")
    If ..RequiredField="" Quit $$$ERROR($$$EnsErrGeneral,"RequiredField is required")
    Quit $$$OK
}
```

The user-stated principle: a BS that needs a setting should refuse to start if the setting is missing, not silently swallow nulls and fail at first message.

> **`OnInit()` without `##super()` on a prebuilt service — silent, and it destroys the input.**
> Symptom: the BS picks the file up and deletes it, **0 messages, 0 Event Log entries, component
> green in the Portal**. There is no error text anywhere; that is the whole difficulty. The base
> `OnInit` is the only place the parser state is initialised — verified on IRIS for Health 2026.1,
> `EnsLib.RecordMap.Service.Base` declares both `OnInit` and `recordMapFull`, and
> `EnsLib.HL7.Service.Standard` declares both `OnInit` and `%Parser`.
>
> Applies to subclasses of **prebuilt** `EnsLib.*.Service.*` and `EnsLib.*.Operation.*`. A direct
> subclass of `Ens.BusinessService` that declares `Parameter ADAPTER` has **no** such obligation —
> its inherited `OnInit()` does nothing by default (ESQL §6.5 "Initializing the Adapter"), so
> `##super()` there adds nothing.
>
> Put `##super()` FIRST rather than `Quit ##super()` last: the validation then runs against a fully
> initialised host, and the base `%Status` is propagated instead of discarded.
