/// Rule: BestPractices_Interop_IRIS.md §5.12 "Class-based Ens.BusinessProcess — the async reply is silently discarded unless you ask for it"
/// Validity: Verified against IRIS for Health 2026.1 in a RUNNING production — see the measurement below.
/// Severity: High (the operation runs, the reply is dropped, and the trace shows a completed process).
///
/// Pattern: a class-based (NON-BPL) Business Process. `bpl` recommends this shape when a BPL
/// diagram stops being readable, and CR-1 is a rule about it — but before this file the bank had
/// only `Ens.BusinessProcessBPL`, so "BP" and "BPL" were effectively synonyms here.
///
/// THE ONE ARGUMENT THAT DECIDES WHETHER THIS WORKS, and it is the third positional one:
///
///     ..SendRequestAsync(target, request, pResponseRequired, pCompletionKey, pDescription)
///                                        ^^^^^^^^^^^^^^^^^^
///
/// MEASURED, by running both versions in a real production and counting callbacks:
///
///   pResponseRequired    OnRequest   BO ran   OnResponse   OnComplete
///   1  (correct)             1          1          1           1
///   0  (the defect)          1          1          0           1
///
/// Read the `0` row carefully, because every instinct about it is wrong. The operation DID run and
/// DID produce a response. Nothing failed. The reply simply was never routed back, so `OnResponse`
/// is never entered, whatever you wrote in it never executes, and the process completes
/// **successfully**. In the Visual Trace you see a completed BP with a response from the operation;
/// what you cannot see is that your own handling of it did not happen.
///
/// The default is 1, so the defect requires writing `0` — which people do when they mean "I do not
/// need to block here". That is not what it means. Async vs sync is `SendRequestAsync` vs
/// `SendRequestSync`; `pResponseRequired` is "will a reply be routed back to me at all".
///
/// HOW COMPLETION ACTUALLY WORKS, since it is the other half of the confusion. Returning `$$$OK`
/// from `OnRequest` does NOT complete the process while replies are outstanding: the framework
/// tracks them in `..%MasterPendingResponses` and completes only when the last one has been
/// handled, at which point `OnComplete` runs and its `response` is what the caller receives. With
/// `pResponseRequired = 0` there is nothing to wait for, so completion is immediate — which is why
/// the defect looks like a fast, healthy process.
///
/// THE CALLBACK SIGNATURES ARE NOT GUESSABLE. Verified against %Dictionary.CompiledMethod:
///   OnRequest(request, *response)
///   OnResponse(request, &response, callrequest, callresponse, pCompletionKey)
///   OnComplete(request, &response)
///   OnError(request, &response, callrequest, pErrorStatus, pCompletionKey)
/// `callresponse` is the reply from the target; `response` is what THIS process returns. Assigning
/// one to the other is the normal body of OnResponse and is easy to get backwards.
///
/// pCompletionKey IS HOW YOU TELL REPLIES APART. With more than one outstanding call, OnResponse is
/// entered once per reply and the key is the only thing that says which. Omit it and a multi-call
/// process cannot route its own replies.
Class Example.BP.OrderFulfil Extends Ens.BusinessProcess
{

/// Where the order goes. A config-item name, resolved at runtime — a typo here is a runtime
/// failure, not a compile one, and tier-1 C8 only checks names inside a production definition.
Property VendorTarget As Ens.DataType.ConfigName [ InitialExpression = "BO.Vendor" ];

Parameter SETTINGS = "VendorTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems}";

/// Entry point. Returning $$$OK here does NOT complete the process — see the header.
Method OnRequest(request As Example.MSG.OrderEvent, Output response As Ens.StringContainer) As %Status
{
    // pResponseRequired = 1. Writing 0 here is the defect this example exists for: the operation
    // still runs, and OnResponse below never executes.
    Quit ..SendRequestAsync(..VendorTarget, request, 1, "vendor")
}

/// One call per reply. `callresponse` is the vendor's answer; `response` is ours.
Method OnResponse(request As Example.MSG.OrderEvent, ByRef response As Ens.StringContainer, callrequest As %Persistent, callresponse As %Persistent, pCompletionKey As %String) As %Status
{
    // The key is the only thing distinguishing replies once there is more than one outstanding.
    If pCompletionKey = "vendor" {
        Set response = callresponse
    }
    Quit $$$OK
}

/// Runs once, after the last outstanding reply has been handled. Its `response` is what the
/// caller receives.
Method OnComplete(request As Example.MSG.OrderEvent, ByRef response As Ens.StringContainer) As %Status
{
    If '$IsObject($Get(response)) {
        Set response = ##class(Ens.StringContainer).%New("no vendor response")
    }
    Quit $$$OK
}

/// Without this, a failing call leaves the process to the framework's default handling and the
/// reason is only in the Event Log. `response` is still what the caller gets, so set it.
Method OnError(request As Example.MSG.OrderEvent, ByRef response As Ens.StringContainer, callrequest As %Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
    Set response = ##class(Ens.StringContainer).%New("vendor call failed: " _ $system.Status.GetErrorText(pErrorStatus))
    // Returning the error status propagates the failure; returning $$$OK swallows it. Choose
    // deliberately -- swallowing here is how a broken downstream becomes invisible upstream.
    Quit pErrorStatus
}

}
