/// Rule: BestPractices_Interop_IRIS.md §5.15 "A bare `%String` rejects, it does not truncate — and `MAXLEN=""` has a second ceiling"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: Medium (the data is safe; the cost is time spent diagnosing the wrong failure).
///
/// Pattern: the three `%String` shapes a canonical message actually chooses between, in one class
/// so the contrast is readable. Its companion `tdd-maxlen-truncation.cls` executes all three.
///
/// WHY THIS FILE EXISTS AT ALL. `MAXLEN = ""` is the mitigation `messages` and `soap-bo` have
/// prescribed since the plugin began, and before this file a grep for it across the whole bank
/// returned **zero**. The recommended fix appeared in no compiled artefact — so nothing established
/// that it even parses, let alone what it does at the top of its range.
///
/// MEASURED, one property, four paths, on 2026.1:
///
///                          50 chars                    51+ chars
///     %Save()              saved, reads back 50        ERROR #7201
///     %ValidateObject()    $$$OK                       ERROR #7201
///     SQL INSERT           SQLCODE=0                   SQLCODE=-104 ... failed validation
///     in memory after Set  50                          THE FULL LENGTH, untouched
///
/// The last row is the one that matters, and it is why three skill sites had to change in v1.36.0.
/// A bare `%String` does **not** silently truncate: the value is held intact in memory and refused
/// at every persistence boundary. "Silently truncated, no error, the data is just gone" was wrong
/// on both halves, and describing a loud failure as a silent one sends you looking for missing text
/// instead of reading the `#7201` you already have.
///
/// NOT THE SAME THING, and the reason this header says so twice: a value cut at a SEPARATOR is a
/// different mechanism. A RecordMap record separator left empty becomes `$char(32)`, so a value
/// containing a space splits — and that one IS silent, with `$$$OK` (see `business-services`). One
/// visible symptom, two causes; the correction above was applied at three sites and deliberately
/// not at that one.
///
/// THE SECOND CEILING, which no prose anywhere had noticed. `MAXLEN = ""` is bounded by
/// `$$$MaxStringLength` = **3,641,144** — the number the skills quote, and it is exactly right.
/// But the STORABLE maximum is lower than the legal string length. Measured on `Unlimited` below:
///
///     10,000 / 100,000 / 500,000 / 1,000,000 / 2,000,000 / 3,000,000 / 3,600,000  all save and
///                                                                                 read back intact
///     3,641,144 (the ceiling exactly):
///         %ValidateObject()  ->  OK
///         %Save()            ->  ERROR #5002: ObjectScript error: <MAXSTRING>%SaveData+18^<Class>.1
///
/// Two lessons in that split. The validator and the saver DISAGREE, so "it validates" is not "it
/// stores" — the row is assembled into one global node alongside the object's other data, and the
/// assembly is what overflows. And the error names a GENERATED ROUTINE, not your property, so it
/// reads like a platform fault rather than a field that is too big. `#7201` tells you which field;
/// `#5002 <MAXSTRING>` tells you nothing you can act on.
///
/// `%Persistent` IS LEFTMOST, per §5.10 — this class has its own extent, which is what lets the
/// companion test read rows back and count them.
Class Example.MSG.MaxLenBoundaries Extends (%Persistent, Ens.Request)
{

/// The default. `%String` with no MAXLEN is `MAXLEN=50`, and 51 chars is a hard `#7201` on save.
/// Left bare deliberately: this is the shape the trap arrives in, and the test asserts against it.
Property Bare As %String;

/// Sized to the source. This is the right default for text from a known field -- an HL7 PID-5
/// family name, a street, a code description. Wide enough not to reject real data, narrow enough
/// that a wildly wrong value is still caught at the boundary rather than stored.
Property Sized As %String(MAXLEN = 200);

/// Unbounded free text: clinical notes, OBX/NTE runs, a JSON blob, base64. Storable well into the
/// millions of characters -- but see the header for what happens at the ceiling itself, and prefer
/// %Stream.GlobalCharacter well before it rather than at it.
Property Unlimited As %String(MAXLEN = "");

}
