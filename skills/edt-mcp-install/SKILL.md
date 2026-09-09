---
name: edt-mcp-install
description: Install or update EDT-MCP into local 1C EDT on Windows and sync this plugin's MCP endpoint for Codex.
---

# EDT MCP Install

Use this skill when the user asks to install, update, or bootstrap EDT-MCP for Codex on Windows.

## Workflow

1. Run the setup script from the plugin root:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1
```

2. If the user gave a workspace path or wants persistent MCP auto-start, pass the workspace and switches:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 `
  -WorkspacePath 'C:\path\to\workspace' `
  -EnableAutoStart `
  -EnablePlainTextMode
```

3. If the user uses a non-default port or auth token, pass them explicitly so `.mcp.json` matches EDT:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 `
  -Port 8766 `
  -Token 'shared-token'
```

4. If EDT autodetection fails, ask the user for the full path to `1cedt.exe` and rerun with `-EdtExecutable`.

5. After success, tell the user to restart EDT.

## Notes

- Default endpoint is `http://localhost:8765/mcp`.
- The script patches `1cedt.ini` with `-DnativeFormBufferedLayoutRender=true` when needed.
- The script can write workspace preferences only when `-WorkspacePath` is known.
