# Edit the saved profile alias in the Windows manager

Status: completed. Owner: unisong. Date: 2026-11-27.

Replace the independent note editor with a modal editor for the same registry alias used during account creation. Use the existing CLI with the exact saved ID; leave credentials, the active selection and private note files untouched. Remove the note column and note persistence code. Keep the add and edit forms consistent with the CLI length limit. ID-based launchers continue to work; alias-based launchers must use the new name.

Verify with WPF self-tests and isolated file-backed profiles, including duplicate aliases, cancellation, same-email selection and persistence after reloading. Run the repository full harness and deploy the tested GUI. Revert the wrapper changes to roll back; aliases remain ordinary CLI aliases.

The source and installed WPF self-tests and isolated file-backend checks passed. The real CLI persisted the Chinese alias on the selected fixture ID, preserved the active same-email sibling and its credentials, and the wrapper rejected a case-insensitive duplicate. No live account was renamed. The full harness passed format, lint, secrets, docs, contracts, vet and build before stopping on existing Windows permission, terminal and macOS path test failures.
