# IRIS SQL dialect — quick cheat-sheet

Kept out of the skill body because it is a SQL topic, not an inbound-service one. For SQL
reached through an outbound adapter see `business-operations` and its `references/jdbc-sql.md`.

## IRIS SQL dialect — quick cheat-sheet

When a RecordMap BS reads/writes through a SQL Gateway, or you verify a run with `iris_query`, keep
these IRIS-SQL specifics in mind:

- **Class ↔ table names.** A persistent class `Pkg.Sub.Cls` projects to SQL table `Pkg_Sub.Cls` —
  package dots become `_`, and the **last** dot separates schema from table. So class `Ens.Util.Log`
  is table `Ens_Util.Log`; `Ens.MessageHeader` stays `Ens.MessageHeader`. Real interop tables:
  `Ens_Util.Log` (event log), `Ens.MessageHeader` (message headers), `EnsLib_*` schemas for adapter data.
- **Reserved words.** `DOMAIN`, `LANGUAGE`, `OUTPUT`, `CONNECTION`, `DEFAULT`, `USER`, `VALUE`, `SECTION`
  and friends are reserved. If a column/table is named one of them, **delimit it with double quotes**
  (`SELECT "Connection" FROM …`). Unquoted, you get SQLCODE -1/-12.
- **ObjectScript is not SQL.** `iris_query` runs SQL SELECTs only. `set`/`write`/`do`/`##class(...)`,
  `&sql(...)`, and `^global` references are ObjectScript — run them with `iris_execute`, not `iris_query`.
- **Discover, don't guess.** Before querying, use `iris_table_info` (or `docs_introspect`, or the
  `Agent(subagent_type="iris-interop-skills:introspect-dont-guess")` — an agent, not a skill; with no agent tool, follow `interop`
  §"Resolving real names") to get the real table/column names rather than guessing
  system-catalog tables — and on `SQLCODE -30 Table not found`, the next call is introspection,
  never a differently-guessed name. Collection properties project to a child table **in the
  parent's schema** — projection rule and example: `messages` §Collections.
