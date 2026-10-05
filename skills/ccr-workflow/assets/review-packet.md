# Peer-review packet: <CCR ID> "<title>"

For the **peer reviewer**, who is never the author. Prepared by the agent from the session; the reviewer
decides.

## What the change does
<Two or three lines, in the customer's terms. Refer to the CCR's planning fields, do not restate them.>

## Items submitted
| Item | Action | Why |
|---|---|---|
| `<Name.CLS>` | edit / add / delete | … |

## Evidence
- **Unit tests:** `<Test class>`, with the result of the last run (pass count and date).
- **End-to-end:** <what was sent, what arrived, where to look (Message Viewer / Visual Trace session ids)>.
- **Negative case:** <what must not happen, and that it did not>.

## Risks and what to look at closely
- <Settings that differ per environment, and how they are set>.
- <Any behaviour change for existing flows>.
- <Anything the author decided against the plan, and why>.

## Not in this CCR
<Improvements noticed but left out on purpose, each proposed as a separate CCR.>
