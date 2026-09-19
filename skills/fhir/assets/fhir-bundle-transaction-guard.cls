/// Rule: BestPractices_Interop_IRIS.md §4.12 "`Bundle.type` decides whether all-or-nothing applies, and `batch` satisfies the prose while breaking the guarantee"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and RUN; the platform behaviour read from the shipped processor.
/// Severity: High (a `batch` Bundle looks identical to a caller and leaves partial data on failure).
///
/// Pattern: refuse a Bundle that is not a `transaction`, before it reaches the FHIR endpoint. That is the
/// whole job. **It deliberately does not re-implement transaction semantics** -- the server has them, and
/// a second implementation in your code would be a second thing to get wrong.
///
/// WHY A GUARD IS NEEDED AT ALL. `skills/fhir` says "Send the Bundle as a transaction so all-or-nothing
/// semantics apply server-side" and says nothing about `batch`. A `batch` Bundle is structurally identical
/// in every respect a casual check would notice: same `resourceType`, same `entry` array, same resources.
/// Measured with `%DynamicObject` and no server present at all:
///
///     {"resourceType":"Bundle","type":"batch","entry":[...]}
///         resourceType = Bundle      type = batch      entry.%Size() = 1
///
/// So "is it a Bundle?" and "does it have entries?" both pass. Only `type` distinguishes them.
///
/// WHAT THE DIFFERENCE ACTUALLY IS, read from the shipped implementation on this instance --
/// `HS.FHIRServer.DefaultBundleProcessor`:
///
///     ProcessBundle       // Transaction Processing:
///                         If (tBundleType="transaction") { Set isTransaction = 1 }
///                         } elseif (tBundleType="batch") {          <-- accepted, isTransaction = 0
///                         If (tBundleType="transaction") || (tBundleType="batch") {
///                         $$$ThrowFHIR($$$HSFHIRErrInvalidBundleTypeForTransaction, tBundleType,
///                                      $$$OutcomeIs(400, "error", "invalid"))
///
///     ExecuteBundleMain   // For transaction, if an interaction fails then quit, perform TROLLBACK,
///                         if (pBundleType = "transaction") { ... }
///                         // Abort the transaction and return an Operation Outcome
///
/// Three facts follow, and all three matter to a caller:
///   1. **Only `transaction` and `batch` reach the processor.** Any other type -- `collection`,
///      `document`, `message`, `searchset` -- is rejected with an OperationOutcome and **HTTP 400**.
///   2. **`isTransaction` is 1 only for `transaction`.** `batch` is accepted with it set to 0.
///   3. **The rollback branch is guarded by that same flag.** A failed entry in a `batch` leaves the
///      entries that already succeeded in place; there is no `TROLLBACK` on that path.
///
/// So a `batch` Bundle does not fail loudly and does not roll back. It returns 200 with a
/// `batch-response` whose individual entries carry their own statuses -- and a caller that checks only
/// the outer HTTP status concludes the whole Bundle was applied.
///
/// NOT MEASURED BEHAVIOURALLY, and stated as such: no FHIR endpoint is configured in the gate namespace
/// (`HS_FHIRServer.ServiceConfigData` does not exist there, SQLCODE -30), so a failing `transaction` was
/// not actually posted and rolled back here. The three facts above are read from the shipped
/// implementation, not executed. The oracle pins that implementation text, so an IRIS upgrade that
/// changes the branching breaks the test -- which is exactly when this section needs re-reading.
Class Example.UTL.FhirBundleGuard Extends %RegisteredObject
{

/// The only `Bundle.type` that gives all-or-nothing.
Parameter REQUIRED As STRING = "transaction";

/// Accepted by the processor but WITHOUT rollback. Named so the refusal can say why.
Parameter PARTIAL As STRING = "batch";

/// Check a Bundle before sending it. Returns $$$OK, or an error naming what was wrong.
/// pBundle is the parsed Bundle; take a %DynamicObject so this works on a stream, a string or a
/// response body without the caller having to know which.
ClassMethod Check(pBundle As %DynamicObject) As %Status
{
    If '$IsObject(pBundle) {
        Quit $$$ERROR($$$GeneralError, "no Bundle supplied")
    }
    // `.resourceType` on a %DynamicObject that lacks the key returns "" rather than raising, so the
    // absent case and the wrong-value case are both covered by one comparison.
    If pBundle.resourceType '= "Bundle" {
        Quit $$$ERROR($$$GeneralError, "not a Bundle: resourceType is '" _ pBundle.resourceType _ "'")
    }
    Set tType = pBundle.type
    If tType = ..#REQUIRED {
        Quit $$$OK
    }
    // The case worth its own message: accepted by the server, silently not atomic.
    If tType = ..#PARTIAL {
        Quit $$$ERROR($$$GeneralError, "Bundle.type is 'batch': the server accepts it and applies each entry independently, so a failure leaves the successful entries committed. Use 'transaction' for all-or-nothing.")
    }
    If tType = "" {
        Quit $$$ERROR($$$GeneralError, "Bundle.type is absent -- the FHIR server rejects the post with HTTP 400 and an OperationOutcome")
    }
    Quit $$$ERROR($$$GeneralError, "Bundle.type is '" _ tType _ "', which the bundle endpoint rejects with HTTP 400. Only 'transaction' and 'batch' reach the processor, and only 'transaction' rolls back.")
}

/// Convenience for a caller holding JSON rather than an object. A parse failure is reported as itself
/// and never as a bad Bundle type -- they need different fixes.
ClassMethod CheckJson(pJson As %String) As %Status
{
    Try {
        Set tBundle = ##class(%DynamicObject).%FromJSON(pJson)
    }
    Catch tException {
        // `Return`, not `Quit`: a `Quit <expr>` inside a Try or Catch block is #1043 QUIT argument not
        // allowed. See §5.20 -- the same trap, in a DTL <code> block.
        Return $$$ERROR($$$GeneralError, "the payload is not valid JSON: <" _ tException.Name _ ">")
    }
    Quit ..Check(tBundle)
}

}
