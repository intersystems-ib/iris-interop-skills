# <CCR ID> "<title>": planning fields (draft for the author)

Write every plan so that someone else could follow it, in any environment. Use `<env>` for anything that
differs per environment: ports, hosts, credentials, URLs. The author pastes these into the CCR and runs
`markPREPComplete`. The agent never does.

## Implementation Plan
1. Load the <CCR ID> ItemSet into `<env>`. It contains:
   - classes: `<Pkg.Tipo.Name>` (<role>), …;
   - production hosts, as decomposed items of `<Production>`: `<Host>` (<adapter or role>), …;
   - lookup tables, schemas and other items: …
2. In `<Production>`, check that <hosts> are present and enabled, with <key settings>.
3. Set the `<env>` values: <setting → where it comes from>. Prefer System Default Settings.
4. Update the production. What is expected afterwards: <one line of behaviour>.

## Backout Plan
1. Stop the inflow first: disable <inbound host>, then <other hosts>, and update the production.
2. Remove <hosts> from `<Production>` and delete <new classes>, or load a backout CCR that restores the previous
   ItemSet.
3. Confirm that `<Production>` runs with only its previous items, and that nothing else changed.

## Testing Plan
1. Unit tests: `<Test class>`. <N> cases, all passing: <what each proves>.
2. End-to-end: send <fixture or message> to <host>. Expected: <ACK> and <what arrives where>.
3. Negative case: <input that must NOT be processed>. Expected: <no delivery, no error, no alert>.
4. In Message Viewer, Visual Trace and the Event Log: <sessions and absence of errors>.
5. In LIVE: <what must not be run there, and the reduced check instead>.
