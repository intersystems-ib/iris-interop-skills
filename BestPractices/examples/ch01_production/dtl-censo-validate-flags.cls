/// Rule: BestPractices_Interop_IRIS.md §1.21 "RecordMap field types are not per-record validation, and what they do instead differs by type"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and RUN through Transform().
/// Severity: High (the alternative is a record that either carries bad data or never exists).
///
/// Pattern: validate per record HERE, where a failure is a message you can route, rather than in the
/// RecordMap field types, where it is either invisible or an exception.
///
/// WHAT THIS REPLACES. `recordmap-typed-fields-fixture.cls` measures what the types actually do:
/// `%Integer` accepts `"ABC"` at parse and only objects at `%Save()`; `%Date` raises `<ZODAT>` inside a
/// generated method; and a wrong field count is not checked at all, so extras are discarded silently.
/// None of those gives you a record you can send to an error operation.
///
/// THE RULE THIS FILE EMBODIES: never reject by omission. Every record becomes a message. A bad one
/// arrives with `IsValid = 0` and a `Problems` string, so a routing rule can send it somewhere and a
/// human can see it in Visual Trace. A dropped record shows **nothing at all**, which is the same thing
/// an empty input directory shows.
///
/// ORDER MATTERS IN ONE PLACE. `Beds` is only set once the checks have passed. Assigning the typed
/// property first and validating afterwards would leave a consumer reading a coerced value from a record
/// the transform had already judged invalid.
Class Example.DT.CensoValidateFlags Extends Ens.DataTransformDTL [ DependsOn = Example.MSG.CensoValidated ]
{

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='Example.MSG.CensoValidated' targetClass='Example.MSG.CensoValidated' create='new' language='objectscript'>
<assign value='source.PatientId' property='target.PatientId' action='set'/>
<assign value='source.BedsRaw' property='target.BedsRaw' action='set'/>
<assign value='source.AdmittedRaw' property='target.AdmittedRaw' action='set'/>
<assign value='source.Ward' property='target.Ward' action='set'/>
<code>
<![CDATA[
 // Accumulate REASONS rather than stopping at the first. A record with two problems should report
 // both, or fixing one just produces the same rejection again.
 set problems = ""
 if source.PatientId = "" {
   set problems = problems_$select(problems="":"",1:"; ")_"PatientId is empty"
 }
 // The check %Integer would not have made at parse time.
 if source.BedsRaw = "" {
   set problems = problems_$select(problems="":"",1:"; ")_"Beds is empty"
 } elseif '$isvalidnum(source.BedsRaw) {
   set problems = problems_$select(problems="":"",1:"; ")_"Beds is not a number: "_source.BedsRaw
 } elseif (source.BedsRaw < 0) {
   set problems = problems_$select(problems="":"",1:"; ")_"Beds is negative: "_source.BedsRaw
 }
 // The check %Date would have RAISED on. TWO THINGS ARE LOAD-BEARING and both were measured:
 //   format 5 is the one that parses YYYY-MM-DD  ($zdateh("2026-09-19", 5, ...) = 67832)
 //   the NINTH argument -1 makes it RETURN -1 instead of raising <ILLEGAL VALUE>
 // $zdateh(v, 1) raises even on a VALID date, because format 1 is not this layout; and format -1 is
 // not a format at all. Note an earlier draft passed the wrong format AND ten arguments and COMPILED
 // CLEAN -- ObjectScript does not check this at compile time, exactly as §6.20 describes.
 if source.AdmittedRaw = "" {
   set problems = problems_$select(problems="":"",1:"; ")_"Admitted is empty"
 } elseif ($zdateh(source.AdmittedRaw, 5, , , , , , , -1) = -1) {
   set problems = problems_$select(problems="":"",1:"; ")_"Admitted is not a date: "_source.AdmittedRaw
 }
 set target.Problems = problems
 set target.IsValid = $select(problems="":1, 1:0)
 // ONLY NOW is the typed property filled, and only when every check passed.
 if problems = "" {
   set target.Beds = source.BedsRaw
 }
]]>
</code>
</transform>
}

}
