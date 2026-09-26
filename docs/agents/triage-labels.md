# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## After the build

One more label, not one of the triage roles: `ready-for-qa`. It marks a ticket that is built, committed and installed, and is waiting for the maintainer to use it in the real app. Such a ticket is assigned to the maintainer and carries a comment on how to use and try the change. The maintainer closes it when it's done, or comments with feedback, which sends it back to `ready-for-agent`. Agents don't close a ticket that's in QA.

QA is **blocking** or **non-blocking**. Blocking QA holds the pull request: it doesn't merge until the QA ticket is closed. For non-blocking QA, the original ticket is closed and a new QA ticket, linked to it both ways, carries the steps to try. The maintainer says which; in effort `shipyard-0-0-1` every change is blocking.

Edit the right-hand column to match whatever vocabulary you actually use.
