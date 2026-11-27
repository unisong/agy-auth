# Edit notes on saved Windows profiles

Status: completed. Owner: unisong. Date: 2026-11-27.

## Objective and scope

Add an editable note to each saved configuration in the Windows account manager. Keep notes separate from aliases, OAuth snapshots and the Go CLI so existing shortcuts and selectors keep their meaning.

## Decision and rollback

Store one UTF-8 text file per exact profile ID under the ignored `private/profile-notes/` directory. Replace individual files atomically; deleting a configuration in the GUI also clears its note. Revert the Windows GUI files to roll back without migrating accounts.

## Acceptance and verification

Exercise writing and replacing Chinese notes, cancellation, clearing, a fresh list load, same-email profile isolation and GUI deletion using fictional profiles in a temporary notes directory. Run the Windows UI self-test and the repository verification profile. Deploy the tested GUI to the existing launcher location and push only source changes.

## Completion

The source and deployed WPF self-tests both passed, including exact-profile persistence, dialog cancellation and deletion cleanup. Inspected the minimum-size window with a saved Chinese note. The full Go harness passed format, lint, secrets, docs, contracts, vet and build, then stopped on the previously documented Windows failures involving permissions, terminal behavior and macOS paths. No real account was edited or switched during verification.
