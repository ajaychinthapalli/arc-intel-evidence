# Contributing

This repository documents the deployment and operation of `arc-intel`. Keep it private; its evidence
includes infrastructure identifiers and internal hostnames.

## Evidence and documentation

- Do not add credentials, tokens, private keys, passwords, or other secret values. Review captured output
  before committing it, and redact sensitive details that are not already intentionally documented.
- Preserve the capture sequence and diagnostic context, but redact sensitive values in both existing and new
  evidence. New captures should include the capture time, timezone, cluster, and source, and should be added
  under the appropriate `evidence/` phase.
- Update `TIMELINE.md` and `evidence/README.md` when adding evidence. Update the relevant docs and root
  `README.md` when changing the implementation record or repository layout.
- Review generated snapshots from `scripts/collect-final-state.sh` for sensitive or irrelevant output before
  committing them.

## Changes

Submit focused changes through a pull request. Include the reason for the change and link the relevant
evidence or follow-up item where applicable.
