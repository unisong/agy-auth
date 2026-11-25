# ADR 0006: Optional Windows account-manager wrapper

- Status: Accepted
- Date: 2026-11-25

## Context

This fork has a locally deployed Chinese account manager. Publishing the executable and installation directory directly would expose private state and make the paths machine-specific. Console-hosted PowerShell shortcuts also leave Windows Terminal windows open.

## Decision

Keep the optional source-only wrapper under `windows/`, using built-in WPF/PowerShell and a locally compiled C# GUI-subsystem launcher. The Go executable remains the credential authority. OAuth is isolated and verified before import without activation. Tests use fake file-backed credentials, never the real keyring.

Do not include credentials, settings, screenshots, binaries, local state, or the independent localization project. Preserve existing upstream CLI and npm behavior. A setup script builds both executables locally and generates direct GUI shortcuts.

Treat the direct script exit code as completion. Drain redirected logs for a bounded period after exit because a persistent child may inherit the pipes.

## Consequences

Windows users need Go and the installed .NET Framework compiler for initial setup. The launcher is rebuilt separately when its source changes. The wrapper remains optional and does not change cross-platform packages or release versioning.
