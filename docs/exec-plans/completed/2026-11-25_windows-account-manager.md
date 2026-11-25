# Publish the Windows account manager

| Field | Value |
|---|---|
| Status | completed |
| Owner | unisong |
| Date | 2026-11-25 |
| Related | [Windows UI](../../../windows/README.md) |

## Objective

Publish the working local Chinese WPF account manager and console-free launcher in this fork, with enough setup instructions to rebuild from a clean checkout.

## Scope

- Export only UI, launcher, local update scripts, and isolated verification code into `windows/`.
- Preserve DPI-aware rendering, window placement, explicit account switching, and bounded completion of inherited output pipes.
- Add configuration examples and a local build/setup script; leave credentials, machine configuration, screenshots, executable files, and caches untracked.
- Keep the Go CLI, npm package version, release workflow, and installed production deployment unchanged.

## Risks

Personal paths or account metadata must not leak through generated previews or settings. Tests must use fixtures and file storage, never the real keyring. Existing upstream tests contain platform assumptions on Windows; report those failures without bypass flags.

## Acceptance criteria

- [x] A checkout can build the GUI launcher and CLI and generate a windowless shortcut.
- [x] UI, placement, isolated profiles, and inherited-pipe completion checks pass.
- [x] Staged source contains no live configuration or generated artifacts.

Publication is performed after this implementation commit, with the remote hash verified in the task report.

## Verification plan

Run `go run ./cmd/harness verify --profile full`, Windows setup, UI self-test, placement verification, isolated profile verification, launcher no-console check and completion regression. Review staged files and run secret/doc checks.

## Rollback

Revert the publication commit; there are no changes to the existing user's live credentials or installed application.

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-11-25 | Keep the wrapper under `windows/`, built locally | Preserve the upstream CLI distribution and avoid publishing machine-specific binaries or state |
| 2026-11-25 | Replace local path assumptions with settings and repository discovery | Make the source export rebuildable on another Windows machine |
| 2026-11-25 | Save window placement with temporary-file replacement | Follow the repository atomic-write invariant without changing the saved schema |

## Completion

- Setup built the CLI and launcher and generated shortcuts in the new repository directory.
- `windows/Verify.ps1` passed: fake-account UI, placement, isolated consumer/GCP switching, no-console launch, and inherited-pipe completion (including success/failure result windows).
- Placement regression passed again after atomic save was added. Staged privacy/artifact and Git whitespace checks passed.
- Full harness attempted: formatting, lints, secret scan, docs/version, contracts, vet and build passed. It stopped at upstream Windows short-test failures involving Unix permissions, macOS paths, terminal colors/spinner and key-event shutdown. Race and npm phases were not reached; full harness is not reported as passed.
- Existing production deployment, account registry and real client were not changed or switched by publication tests.
