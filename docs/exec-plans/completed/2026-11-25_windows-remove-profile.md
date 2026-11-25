# Remove a saved profile from the Windows GUI

| Field | Value |
|---|---|
| Status | completed |
| Owner | unisong |
| Date | 2026-11-25 |

## Objective and scope

Add a Delete configuration action to the Chinese WPF manager and deploy the tested change to the local installation. Use the existing CLI remove command with the exact saved profile ID and without logout. Do not change the Go CLI, actual accounts, subscriptions, or shared launcher.

## Acceptance criteria

- The action is disabled with no selection and while busy.
- A cancel-default dialog identifies email, alias, mode and Cloud project; it explains that current login and subscriptions remain active.
- Cancellation makes no CLI call. Confirmation removes only the selected saved ID and refreshes the list.
- Removing a saved current profile preserves live credentials and does not re-add the profile on refresh.
- Tests use fictional UI data and isolated file-backend credentials, including same-email consumer/Cloud profiles.

## Verification

Run the UI self-test and isolated profile verification, inspect rendered screenshots, and attempt the full repository harness. Inspect the staged diff and secret scan before committing and pushing the requested change.

## Risks and rollback

Existing shortcuts bound to a deleted ID stop resolving; document this. Removing a saved profile is not a secure erase of historical backups. Never exercise deletion against real accounts during verification. Revert the GUI/source files to roll back; no credential migration is required.

## Completion

- Added a saved-profile button, cancel-default WPF dialog and exact-ID CLI wrapper without logout.
- UI self-tests passed cancellation, confirmation, current-profile notice, busy/empty states and list refresh. Inspected compact and high-DPI confirmation renders.
- Isolated tests passed same-email consumer/Cloud deletion, missing-ID rejection, empty saved list, and unchanged live credential/settings hashes.
- Deployed the GUI/helper files to the existing local installation; reran checks against the installed CLI and verified the real registry hash was unchanged.
- Full harness attempted: format, lint, secrets, docs, contracts, vet and build passed; short tests stopped on existing Windows permission, terminal and macOS-path assumptions. Race/npm phases were not reached.
- No real profile was deleted and no live account switch was performed. Historical credential backups and stale shortcuts are retained, as documented.
