/// Rule: BestPractices_Interop_IRIS.md §5.2 "BS that runs on a schedule: use a custom adapter for wall-clock triggers"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium (the adapter carries the silent failure; this half carries the wiring).
///
/// Pattern: the SERVICE half — the Business Service a custom inbound adapter dispatches into.
/// Read it next to adp-scheduler-inbound-adapter.cls in this directory.
///
/// `Parameter ADAPTER` NAMES THE ADAPTER CLASS, and this is the only link between the two. Get it
/// wrong and the framework instantiates nothing; the item starts, reports no error, and never
/// fires — the same outcome as the missing dispatch in the adapter, reached a different way.
///
/// EXTENDS Ens.BusinessService, NOT THE ADAPTER. Extending the adapter directly is the single most
/// common shape error in this codebase's history and a PreToolUse gate blocks it: the adapter is a
/// COLLABORATOR reached through `..Adapter`, not a superclass.
///
/// pInput IS ALWAYS NULL HERE, and that is not a defect. A scheduled trigger carries no payload —
/// the adapter passes `$$$NULLOREF` — so the service decides for itself what work "now" means. Do
/// not write a null check that returns an error; a null input IS the normal case for this shape.
///
/// YOU CANNOT UNIT-TEST THIS CLASS BY CONSTRUCTING IT. Measured on 2026.1:
///   ##class(<any Ens.BusinessService subclass>).%New()   ->  returns "", NOT an object, no error
/// The `<INVALID OREF>` then surfaces at the next dereference, somewhere unrelated. The supported
/// route is `Ens.Director.CreateBusinessService("<item name>", .svc)` — and it takes the production
/// ITEM name, not the class name; an unregistered name gives
/// `<Ens>ErrBusinessDispatchNameNotRegistered`. That is why the companion test exercises the
/// ADAPTER (which %New()s fine) with a stand-in host, rather than this class.
Class Demo.BS.NightlyExtract Extends Ens.BusinessService
{

/// The link to the adapter. A typo here is silent.
Parameter ADAPTER = "Demo.ADP.SchedulerAdapter";

/// pInput is $$$NULLOREF for a scheduled trigger — see the header.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set tReq = ##class(Example.MSG.OrderEvent).%New()
    Set tReq.OrderId = "NIGHTLY-" _ $ZDate($Horolog, 8)
    Set tReq.EventType = "NEW"

    // Async: a scheduled service should not hold the poll open waiting for downstream work.
    Quit ..SendRequestAsync("Router.Censo", tReq)
}

}
