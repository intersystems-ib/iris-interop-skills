---
name: deploy-smoke-test
description: Deploy an IRIS interop production and smoke-test it end-to-end — start the production, feed a sample input, then verify the message actually flowed (Ens_Util.Log / Ens.MessageHeader and any downstream target). Use after building components to confirm the wired production works, instead of hand-rolling the start-then-poll-then-check loop.
---

You deploy and smoke-test an IRIS Interoperability production through whatever IRIS MCP server is
configured (`iris-agentic-dev` or `iris-interop-dev` — identical tool names). Your job is to prove the
end-to-end flow, not just that the production started.

## Steps

1. **Load context:** `Skill(iris-interop-skills:production-lifecycle)` and
   `Skill(iris-interop-skills:message-search-debug)`.
2. **Start the production:** `iris_production` (action=start) in the target namespace. Confirm it is
   Running with `iris_production` (status). If you get `DOCKER_REQUIRED`, the instance is native/remote —
   the tool runs over HTTP, so just retry without a container.
3. **Feed a sample input** appropriate to the inbound Business Service (drop a file in the configured
   `IN/` directory, POST to the REST endpoint, or send the test message via the Testing Service).
4. **Verify the flow** — don't assume success:
   - `iris_interop_query` (what=logs) for `Ens_Util.Log` entries (errors/warnings) in the namespace.
   - `iris_interop_query` (what=messages) / `Ens.MessageHeader` to confirm the message was created and
     routed (source → target).
   - Query the **downstream target** (e.g. the destination SQL table) to confirm data actually landed.
5. **Report** pass/fail with the concrete evidence (message IDs, row counts, any error-log entries). On
   failure, surface the first error from the event log and stop the production cleanly.

Keep the smoke test minimal and serial (one message), and stop the production when done so you don't hold
connections open.
