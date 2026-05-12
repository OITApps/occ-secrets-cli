# occ-secrets-cli — Lightweight Key Vault helpers (no OCC required)

A minimal install of `occ-fetch-secret` + `occ-store-secret` for users who don't run full OCC — typically non-engineering staff or Windows users.

These are cross-platform Python ports of the OCC bash helpers. Functionally equivalent: same vault selector, same `--vault` / `--name` / `--list` / `--copy` flags, same fallback chain.

## Install

### macOS / Linux

```bash
curl -sSL https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0/install.sh | bash
```

The installer checks for Homebrew, Python 3.8+, and `az` CLI. If any are missing it offers to install them (via `brew`). It also seeds `~/.claude/.occ-vault.json` with your personal vault name (`occ-secrets-<your-upn-prefix>`) and ensures `~/.local/bin` is on your PATH.

### Windows

In **PowerShell** (not cmd):

```powershell
irm https://raw.githubusercontent.com/OITApps/occ-secrets-cli/v1.0.0/install.ps1 | iex
```

The installer checks for `winget`, Python 3.8+, and Azure CLI. If `winget` is present (default on Windows 10/11 with App Installer), it offers to install missing prereqs. Scripts land in `%USERPROFILE%\.local\bin\` and a `.cmd` shim lets you type `occ-fetch-secret` without `.py`.

> **Note on PowerShell execution policy:** if you see "running scripts is disabled," run once in an elevated PowerShell: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Prerequisites checked by the installer

| Tool | Why | Install fallback |
|---|---|---|
| Python 3.8+ | The scripts are Python | macOS: `brew install python@3.12`; Linux: `apt-get/dnf/pacman`; Windows: `winget install Python.Python.3.12` |
| Azure CLI | All vault access goes through `az keyvault secret …` | macOS: `brew install azure-cli`; Linux: `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash`; Windows: `winget install Microsoft.AzureCLI` |
| (macOS only) Homebrew | Tooling source | Offered to install via the official Homebrew install script |
| (Windows only) winget | Tooling source | Bundled with App Installer; install from Microsoft Store |

The installer never installs anything without an explicit `y` prompt.

## After install

```bash
az login                                                 # one-time, against your OIT identity
occ-fetch-secret --help                                  # see flags
occ-fetch-secret --vault company --list                  # what you have access to
occ-fetch-secret --vault company --name HELPJUICE-API-KEY --copy
```

If you get `403 ForbiddenByRbac`, you're not in the right AAD group yet — email `cse@oit.co` to request membership.

## Differences from full OCC

| Feature | Full OCC | `occ-secrets-cli` |
|---|---|---|
| `occ-fetch-secret` | ✅ bash | ✅ Python (this) |
| `occ-store-secret` | ✅ bash | ✅ Python (this) |
| `occ-fetch-secrets.sh <server>` (MCP batch fetcher) | ✅ | ❌ — full OCC only |
| Catalog routing + fallback chain | ✅ | ❌ — single-vault fetch only |
| MCP server lifecycle | ✅ | ❌ — not in scope |
| Plugins, personas, hooks | ✅ | ❌ — not in scope |

If you need any of the right-column features, install full OCC instead. OIT staff: see the internal vault-access guide on voipdocs for the OCC install link and group-membership workflow.

## Uninstall

macOS / Linux:
```bash
rm "$HOME/.local/bin/occ-fetch-secret" "$HOME/.local/bin/occ-store-secret"
# (optional) rm ~/.claude/.occ-vault.json
```

Windows:
```powershell
Remove-Item "$env:USERPROFILE\.local\bin\occ-fetch-secret.py", "$env:USERPROFILE\.local\bin\occ-fetch-secret.cmd"
Remove-Item "$env:USERPROFILE\.local\bin\occ-store-secret.py", "$env:USERPROFILE\.local\bin\occ-store-secret.cmd"
# (optional) Remove-Item "$env:USERPROFILE\.claude\.occ-vault.json"
```

## Updating

Re-run the install one-liner. Both installers overwrite the existing scripts in place.
