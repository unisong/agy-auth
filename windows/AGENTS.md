# Windows wrapper

- UI code lives in `agy-auth/`; `launcher/` contains the Windows GUI-subsystem launcher. Keep user state, account storage, settings, screenshots, generated shortcuts, caches and binaries ignored.
- Preserve UTF-8 BOM for PowerShell scripts containing Chinese and ASCII/CRLF for `.cmd` wrappers.
- Credentials are handled by the Go CLI. New OAuth uses isolated temporary file storage, verifies the expected email and imports without activation. Never read browser cookies or use live account switches in tests.
- One-click shortcuts target the launcher, not PowerShell. Keep `CreateNoWindow=true`; manual `.ps1` use remains available.
- Parent-process completion must not wait indefinitely for pipe EOF inherited by a daemon. Run `launcher/Verify-ProcessCompletion.cs` after changing capture or completion handling.
- UI self-tests use fictional accounts; placement tests use a temporary file. Never overwrite real `ui-state.json` during tests.
- Saved-profile deletion requires a cancel-default confirmation and an exact stored ID; never pass `--logout` or `--all`. Test deletion only with isolated fake credentials, including same-email profiles and retained live credentials.
- For verification instructions see [README](README.md). Keep fork updates fast-forward-only and refuse dirty tracked source.
