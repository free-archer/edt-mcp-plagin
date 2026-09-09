# EDT MCP Setup Plugin for Codex

Этот репозиторий содержит локальный plugin для Codex, который упрощает подключение [EDT-MCP](https://github.com/DitriXNew/EDT-MCP) к Codex на Windows.

Что делает plugin:

- даёт Codex готовое MCP-подключение на `http://localhost:8765/mcp` через `.mcp.json`
- добавляет навыки для установки и перенастройки EDT-MCP
- кладёт PowerShell-скрипт, который умеет:
  - найти локальный `1cedt.exe`
  - установить EDT-MCP через `p2 director`
  - дописать в `1cedt.ini` флаг `-DnativeFormBufferedLayoutRender=true`
  - при необходимости записать workspace preferences для автозапуска MCP и нужного порта
  - пересобрать `.mcp.json` под выбранный порт и token

## Быстрый сценарий

1. Установить этот plugin в Codex как локальный.
2. Внутри Codex попросить: `установи EDT-MCP в мой EDT`.
3. Plugin запустит `scripts/setup-edt-mcp.ps1`.
4. После завершения перезапустить EDT.

## Установка из GitHub

```bash
# 1. Зарегистрировать репозиторий как marketplace
codex plugin marketplace add free-archer/edt-mcp-plagin

# 2. Установить плагин из него
codex plugin add edt-mcp-plagin@edt-mcp-plagin
```

Проверить установку и убедиться, что имя marketplace/плагина совпало:

```bash
codex plugin list
```

Удалить:

```bash
codex plugin remove edt-mcp-plagin@edt-mcp-plagin
codex plugin marketplace remove edt-mcp-plagin
```

## Ручной запуск скрипта

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1
```

С указанием workspace и автозапуска:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 `
  -WorkspacePath 'C:\work\edt-workspace' `
  -EnableAutoStart `
  -EnablePlainTextMode
```

С нестандартным портом и token:

```powershell
pwsh -File .\scripts\setup-edt-mcp.ps1 `
  -Port 8766 `
  -Token 'my-shared-token'
```

## Что не делается автоматически

- Plugin не правит глобальный `~/.codex/config.toml`, потому что подключение приезжает вместе с plugin через `.mcp.json`.
- Plugin не угадывает ваш EDT workspace, если вы его не передали явно.

## Файлы

- `.codex-plugin/plugin.json` — manifest plugin
- `.mcp.json` — MCP endpoint для Codex
- `skills/` — инструкции для Codex
- `scripts/setup-edt-mcp.ps1` — основной setup/install сценарий
