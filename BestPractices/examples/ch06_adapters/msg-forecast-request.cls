/// Rule: BestPractices_Interop_IRIS.md §6.16 "The typed SOAP BO: the client class belongs in configuration, and what that costs"
/// Validity: Verified against IRIS for Health 2026.1 — compiled.
/// Severity: Medium (it exists so the BO's MessageMap resolves to a real class).
///
/// Pattern: the request the SOAP BO's `MessageMap` keys on. It ships because the fence this replaces
/// named `MyApp.SOAP.WeatherService.GetForecastRequest` and did not provide it, which is exactly why
/// that fence sat in tier 3's **placeholder dependency** bucket and off `snippets_baseline.json` — a
/// complete class the gate extracted, compiled, and then had to excuse.
///
/// `%Persistent` IS LEFTMOST, per §5.10, so this message has its own extent.
Class Example.MSG.ForecastReq Extends (%Persistent, Ens.Request)
{

Property Location As %String(MAXLEN = 100);

/// Sized to the source rather than left bare: §5.15 measured that a bare `%String` is `MAXLEN=50`
/// and REJECTS a longer value with `#7201` rather than truncating.
Property RequestedOn As %String(MAXLEN = 20);

}
