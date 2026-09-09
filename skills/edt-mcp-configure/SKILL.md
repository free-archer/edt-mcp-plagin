---
name: edt-mcp-configure
description: Reconfigure this plugin's EDT-MCP connection when the port, token, or EDT workspace settings change.
---

# EDT MCP Configure

Use this skill when EDT-MCP is already installed, but the connection settings changed.

## Workflow

1. Rebuild the plugin MCP config for the target port/token:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 -SkipEdtInstall
```

2. If the user changed port, token, or wants workspace auto-start, pass explicit values:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 `
  -SkipEdtInstall `
  -WorkspacePath 'C:\path\to\workspace' `
  -Port 8766 `
  -Token 'shared-token' `
  -EnableAutoStart
```

## Notes

- `-SkipEdtInstall` keeps the script in config-only mode.
- If `Allow remote access` is requested, require a non-empty token.
