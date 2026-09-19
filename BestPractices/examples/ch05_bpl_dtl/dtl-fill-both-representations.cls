/// Rule: BestPractices_Interop_IRIS.md §5.24 "A message carrying the same data twice: fill both, and never read the collection as a scalar"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled and RUN through Transform().
/// Severity: High (filling one side leaves the other silently wrong).
///
/// Pattern: the transform that keeps the two representations of `Example.MSG.SuppliesOrder` in step.
/// Its whole job is that neither side is ever the only one filled.
///
/// THE ONE LINE THAT MATTERS is the `Serialize()` in the `<code>` block. `$ListToString` raises `<LIST>`
/// when handed the collection itself -- measured -- so the sequence is
/// `$ListToString(<collection>.Serialize(), delim)`.
///
/// WHY A `<code>` BLOCK AND NOT AN `<assign>`. There is no DTL assign action that collapses a collection
/// into a delimited string; `action='set'` with `source.SupplyList` as the value would assign the OREF,
/// which renders as `41@%Collection.ListOfDT` and is exactly the defect this file exists to prevent.
///
/// THE LEGACY REPRESENTATION IS LOSSY, and that is the finding worth carrying away. An item that itself
/// contains the delimiter cannot be expressed: measured, `["PEN|LATEX", "GAUZE"]` serialises to
/// `PEN|LATEX|GAUZE`, which a consumer reads back as **three** items. Nothing raises. So this transform
/// rejects such an item rather than producing a string that round-trips to different data.
///
/// DIRECTION. This transform normalises the TYPED side into the legacy one, which is the direction a
/// modern producer needs. The reverse (`$Piece` over the legacy string into the collection) is what an
/// inbound legacy feed needs, and the oracle asserts it round-trips.
Class Example.DT.FillBothRepresentations Extends Ens.DataTransformDTL [ DependsOn = Example.MSG.SuppliesOrder ]
{

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='Example.MSG.SuppliesOrder' targetClass='Example.MSG.SuppliesOrder' create='new' language='objectscript'>
<assign value='source.OrderId' property='target.OrderId' action='set'/>
<!-- Copy the typed side item by item. `action='append'` on a collection property is the DTL way; a
     plain 'set' of the whole collection would share one object between two messages. -->
<foreach key='i' property='source.SupplyList'>
<assign value='source.SupplyList.GetAt(i)' property='target.SupplyList' action='append'/>
</foreach>
<!-- AND NOW THE LEGACY SIDE, from the typed one.
     NO EMPTY-COLLECTION GUARD. `$select(Count()=0:"", ...)` looks prudent and is INERT: measured,
     Serialize() of an empty collection is "" and $ListToString("") is "", so the guard never changes
     an outcome. Removing it left the suite green, which is how it was found.
     THE CHECK THAT IS NOT INERT is the delimiter collision. An item containing "|" serialises into
     "PEN|LATEX|GAUZE", indistinguishable from THREE items — the legacy representation is lossy and
     silently so. $$$ThrowStatus inside a <code> block makes Transform() return that error and leaves
     the target unset, which is the loud failure this deserves. -->
<code>
<![CDATA[
 for i=1:1:target.SupplyList.Count() {
   if target.SupplyList.GetAt(i) [ ##class(Example.MSG.SuppliesOrder).#DELIM {
     $$$ThrowStatus($$$ERROR($$$GeneralError, "supply item "_i_" contains the delimiter and cannot be expressed in the legacy representation: "_target.SupplyList.GetAt(i)))
   }
 }
 set target.Supplies = $listtostring(target.SupplyList.Serialize(), ##class(Example.MSG.SuppliesOrder).#DELIM)
]]>
</code>
</transform>
}

}
