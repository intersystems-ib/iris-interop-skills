/// Rule: BestPractices_Interop_IRIS.md §6.11 "Subclassing a prebuilt Business Service — `##super()` first, and what #5478 does and does not enforce"
/// Validity: Verified against IRIS for Health 2026.1 — every enforcement claim below was compiled.
/// Severity: High (the `##super()` omission compiles clean and skips the host's own setup).
///
/// Pattern: subclassing a PREBUILT service — here `EnsLib.RecordMap.Service.FileService` — for the
/// one reason that is legitimate: extra INITIALISATION. Read the next paragraph before copying it.
///
/// WHAT THIS IS NOT FOR. Do not subclass a RecordMap service to reshape records. Its
/// `OnProcessInput` receives the WHOLE FILE as a `%Stream.Object` and there is no per-record hook,
/// so an override replaces the very loop you wanted to use (§1.11). Reshaping belongs in a DTL on
/// the router. Subclass for setup that must happen when the host starts — priming a cache, opening
/// an auxiliary connection, validating configuration — and for nothing else.
///
/// `##super()` FIRST IN OnInit, AND HERE IS WHY IT MATTERS MORE ON SOME HOSTS THAN OTHERS.
/// `OnInit` is not always a no-op you are safely replacing. Measured by reading `Origin` out of
/// %Dictionary.CompiledMethod, which tells you where the implementation actually lives:
///
///   EnsLib.RecordMap.Service.FileService   OnInit origin = EnsLib.RecordMap.Service.Standard
///   EnsLib.HL7.Service.FileService         OnInit origin = EnsLib.HL7.Service.FileService
///   EnsLib.File.PassthroughService         OnInit origin = Ens.Host
///   Ens.BusinessService                    OnInit origin = Ens.Host
///
/// The first two define their OWN OnInit — real setup that your override silently replaces if you
/// forget `##super()`. It compiles either way, the production starts, and the failure appears later
/// as records that do not parse or a host that behaves as if unconfigured. That query is how you
/// check any host before overriding: if Origin is not `Ens.Host`, the base is doing work you need.
///
/// WHAT #5478 ACTUALLY ENFORCES, measured on this host — and it is not what it is usually said to
/// enforce:
///
///   3 args, correct types                        COMPILES
///   2 args (pHint dropped), correct types        COMPILES        <-- arity is NOT enforced
///   3 args, pInput As %RegisteredObject          FAILS #5478     <-- the TYPE is
///   3 args, pHint by value instead of ByRef      COMPILES        <-- ByRef is NOT enforced
///
/// So the enforcement is on the argument TYPES, not on the count. The consequence: you can quietly
/// drop `pHint` and compile clean, and then never see what the framework passed you — for a file
/// service that is where the filename arrives. Declare the full signature, ByRef included, because
/// nothing will tell you that you have not.
///
/// Note also that `Ens.BusinessService` itself enforces nothing here: a 2-arg override on a plain
/// custom service compiles. The #5478 protection exists only when you subclass a PREBUILT host.
Class Example.BS.CensoWithWarmup Extends EnsLib.RecordMap.Service.FileService
{

/// Extra startup work, with ##super() FIRST. Reversing the order, or omitting it, skips
/// EnsLib.RecordMap.Service.Standard's own OnInit — see the header.
Method OnInit() As %Status
{
    Set tSC = ##super()
    Quit:$$$ISERR(tSC) tSC

    // Whatever this host needs before the first file arrives. Failing here stops the host from
    // starting, which is the right outcome: a service that starts without its prerequisites is
    // the silent shape this bank exists to avoid.
    Set ..WarmedAt = $ZDateTime($Horolog, 3)
    Quit $$$OK
}

/// The FULL signature, ByRef included, and it delegates. Dropping `pHint` would compile — see the
/// header — and would lose the filename the framework passes for a file service.
Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
{
    // No per-record work here: the base implements the record loop and the per-record dispatch.
    // Anything record-shaped belongs in a DTL on the router (§1.11).
    Quit ##super(pInput, .pOutput, .pHint)
}

/// Set by OnInit, so "did the warm-up run" is answerable rather than assumed.
Property WarmedAt As %String;

}
