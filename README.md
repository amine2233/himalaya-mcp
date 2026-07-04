# HimalayaMcpCLI

A single Swift executable that works **both** as a classic command-line tool and as a
[Model Context Protocol](https://modelcontextprotocol.io) (MCP) server — sharing one
implementation for every feature.

- **CLI** — powered by [`swift-argument-parser`](https://github.com/apple/swift-argument-parser).
- **MCP server** — powered by the [`swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk).
- **Dependency injection** — Vapor-style container from [`cascade-kit`](https://github.com/amine2233/cascade-kit).
- **Configuration & feature flags** — from [`swift-configuration`](https://github.com/apple/swift-configuration).

The core idea: every feature is written **once** as a `Request` and exposed **twice** — as a CLI
subcommand and as an MCP tool — so the two surfaces can never drift apart.

---

## What it does

Each feature is a `Request` that drives the [`himalaya`](https://github.com/pimalaya/himalaya)
CLI through the injected `HimalayaService`, and is exposed as an MCP tool.

| MCP tool | Arguments | himalaya command |
|----------|-----------|------------------|
| `list_emails` | `folder?`, `page_size?`, `page?`, `account?` | `envelope list` |
| `search_emails` | `query`, `folder?`, `account?` | `envelope list <query…>` |
| `read_email` | `id`, `folder?`, `account?` | `message read <id> --no-headers` |
| `read_email_html` | `id`, `folder?`, `account?` | `message export <id>` → HTML part |
| `list_folders` | `account?` | `folder list` |
| `create_folder` | `name`, `account?` | `folder add <name>` |
| `delete_folder` | `name`, `account?` | `folder delete <name>` |
| `flag_email` | `id`, `flags`, `action` (`add`\|`remove`), `folder?` | `flag add\|remove <id> <flags…>` |
| `move_email` | `id`, `target_folder`, `folder?`, `account?` | `message move <target> <id>` |
| `compose_email` | `to`, `subject`, `body`, `attachments?`, `account?` | `message write` → template |
| `draft_reply` | `id`, `body?`, `reply_all?`, `folder?`, `account?` | `message reply <id>` → template |
| `send_email` | `template`, `attachments?`, `confirm`, `account?` | `message send <template>` |
| `list_attachments` | `id`, `folder?`, `account?` | `attachment download` → temp dir |
| `download_attachment` | `id`, `filename`, `folder?`, `account?` | `attachment download` → temp dir |
| `delete_email` **(experimental)** | `ids`, `folder?`, `account?` | `message delete <id…>` |

The `himalaya` binary is located via `$HIMALAYA_BIN_PATH` (if set, it wins) and otherwise by
searching `PATH`. Notes on the less obvious mappings:

- `search_emails` takes a himalaya filter/sort query (e.g.
  `from alice and subject invoice order by date desc`), split into tokens.
- `compose_email` / `draft_reply` produce a **template** and never send; feed it to `send_email`,
  which refuses unless `confirm=true` (sending is irreversible). Attachments are expressed as
  himalaya MML `<#part>` directives.
- himalaya has no per-attachment listing/selection, so `list_attachments` and
  `download_attachment` download into a throwaway directory and inspect the result.
- `delete_email` is **irreversible** and therefore experimental: it is hidden from `tools/list`
  (and rejected if called) unless `experimental.enabled` / `EXPERIMENTAL_ENABLED=true` is set.

Experimental features are gated behind a configuration flag — hidden from `--help` / `tools/list`
and rejected if invoked — unless `experimental.enabled` is on.

### Folders & labels

himalaya has no separate "label" concept — **labels are folders**. On Gmail-style accounts,
each label is exposed as a folder, typically under a `Labels/` prefix (e.g. `Labels/Important`,
`Labels/Newsletters`), alongside system folders like `INBOX`, `Archive`, `Sent`, `All Mail`,
`Starred`, `Spam`, `Trash`. So every `folder` argument accepts a label path, and:

- **List a label's mail** → `list_emails` with `folder: "Labels/Important"`.
- **Apply a label** (move onto it) → `move_email` with `target_folder: "Labels/Follow Up"`.
- **Create / delete a label** → `create_folder` / `delete_folder` with a `Labels/…` name.
- **Archive** → `move_email` with `target_folder: "Archive"` (there is no dedicated archive command;
  archiving is a move to the `Archive` folder).
- **Flag / unflag** → `flag_email` with `action: "add" | "remove"` and flags like `Seen`, `Flagged`,
  `Answered` (starring in Gmail terms is the `Flagged` flag, or a move to the `Starred` folder).

---

## Architecture

### Modules

```mermaid
graph TD
    subgraph external["External packages"]
        AP["swift-argument-parser"]
        MCP["swift-sdk · MCP"]
        CK["cascade-kit · CascadeKit"]
        SC["swift-configuration"]
    end

    HimalayaMcpCLI["HimalayaMcpCLI<br/>(executable)<br/>CLI + MCP surfaces, app instance"]
    App["App<br/>Request protocol, requests,<br/>ExecutableService, service keys, configure()"]
    AppConfiguration["AppConfiguration<br/>FeatureFlags, HimalayaSettings, ConfigurationLoader"]

    HimalayaMcpCLI --> App
    HimalayaMcpCLI --> AppConfiguration
    HimalayaMcpCLI --> AP
    HimalayaMcpCLI --> MCP
    HimalayaMcpCLI --> CK

    App --> AppConfiguration
    App --> CK

    AppConfiguration --> SC
```

- **`AppConfiguration`** — dependency-light. Resolves `FeatureFlags` and `HimalayaSettings` from the
  environment layered over an optional JSON file (`ConfigurationLoader.resolveAll()`).
- **`App`** — the domain. The `Request` protocol and its implementations, the `ExecutableService`
  abstraction (+ live `ExecutableServiceDefault`), the DI service keys, and the Vapor-style
  `configure(_:)` that registers everything into a container.
- **`HimalayaMcpCLI`** — the executable. Owns the shared `app` container, wires the CLI subcommands and
  the MCP server, and calls `configure(app)` at startup.

### The "write once, expose twice" pattern

```mermaid
graph LR
    subgraph surfaces["Surfaces · HimalayaMcpCLI"]
        CLI["CLI subcommand<br/>e.g. ServeCommand"]
        TOOL["MCP ToolHandler<br/>himalaya tool"]
    end

    REQ["Request.execute<br/>input + application"]
    SVC["ExecutableService<br/>resolved via app.make"]
    OUT["stdout / stderr"]

    CLI -->|builds Input, execute in app| REQ
    TOOL -->|decodes Input, execute in app| REQ
    REQ -->|app.make ExecutableServiceKey| SVC
    SVC -->|runs swift| OUT
```

Both surfaces construct the same typed `Input` and call the same `Request`, which resolves the
`ExecutableService` from the container — so behaviour is identical however the tool is invoked.

### Dependency injection (Vapor-style)

`configure(_:)` registers services into the container once at startup; everything else resolves
them with `make`.

```mermaid
sequenceDiagram
    participant Main
    participant Configure as App.configure
    participant App as app · container
    participant Loader as ConfigurationLoader
    participant Cmd as Command / ToolHandler
    participant Req as Request

    Main->>Configure: await configure(app)
    Configure->>App: register ExecutableServiceKey → ExecutableServiceDefault
    Configure->>Loader: await resolve()
    Loader-->>Configure: FeatureFlags · env over file
    Configure->>App: register FeatureFlagsServiceKey → flags
    Main->>Cmd: run · CLI parse or MCP call
    Cmd->>Req: execute(input, in: app)
    Req->>App: make ExecutableServiceKey
    App-->>Req: ExecutableService
    Req-->>Cmd: output
```

> **Note on naming:** CascadeKit's container types are named `Application` and `Request` — the same
> as our `Request` protocol. We keep our `Request` (a module's own declaration shadows the imported
> one) and refer to the container simply as `Application`.

---

## Requirements

- Swift 6.0+ toolchain
- macOS 15+ (required by `swift-configuration` 1.0)
- The [`himalaya`](https://github.com/pimalaya/himalaya) CLI, installed and configured with at least
  one account — the server shells out to it (found via `PATH` or `$HIMALAYA_BIN_PATH`)
- Optional: [`mise`](https://mise.jdx.dev) to run the build/install tasks below

## Install

**Recommended — per-user install to `~/.local/bin` (via mise).** This keeps the binary in your home
directory (no `sudo`, nothing installed machine-wide):

```bash
mise run install                          # build -c release → ~/.local/bin/himalaya-mcp
mise run install --bin-path /usr/local/bin # …or install to a specific directory
mise run setup-path                       # optional: add ~/.local/bin to PATH in your shell profile
```

`mise run install` builds the release binary and copies it to `~/.local/bin/himalaya-mcp`. Pick a
different directory with `--bin-path <dir>` (or `INSTALL_DIR=/some/dir mise run install`);
`mise run uninstall [--bin-path <dir>]` removes it. `~/.local/bin` is already on `PATH` inside this
project's mise environment; `setup-path` makes that permanent for your interactive shells.
Run `mise tasks` to see everything (`build`, `test`, `run`, `install`, `uninstall`, `setup-path`,
`mcp-add`).

**Manual — without mise:**

```bash
swift build -c release
mkdir -p "$HOME/.local/bin"
install -m 0755 "$(swift build -c release --show-bin-path)/HimalayaMcpCLI" "$HOME/.local/bin/himalaya-mcp"
```

**Development build** (run in place, no install):

```bash
swift build            # debug
swift run HimalayaMcpCLI --help
```

## Usage as a CLI

```bash
himalaya-mcp --help           # if installed on PATH (mise run install)
swift run HimalayaMcpCLI --help   # or run in place from the source tree
```

Besides `serve`, the CLI ships management commands:

```bash
himalaya-mcp doctor                  # check himalaya + all accounts are reachable
himalaya-mcp doctor --account work   # check only one account
himalaya-mcp doctor --json           # machine-readable report (exit code non-zero on problems)

himalaya-mcp setup                   # add/update the entry in Claude Desktop's config
himalaya-mcp setup --check           # verify that entry
himalaya-mcp setup --remove          # remove it
```

`doctor` resolves the `himalaya` binary, discovers accounts via `himalaya account list`, and probes
each by listing its folders — reporting reachability per account (add `--json` for scripting/CI).

## Usage as an MCP server

```bash
himalaya-mcp serve            # installed binary
swift run HimalayaMcpCLI serve    # or from the source tree
```

`serve` speaks JSON-RPC over **stdio**; an MCP host launches it for you. Manual smoke test:

```bash
BIN="$HOME/.local/bin/himalaya-mcp"   # or "$(swift build --show-bin-path)/HimalayaMcpCLI"
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0.0.1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 1
} | "$BIN" serve
```

> **Note:** in `serve` mode stdout is reserved for the JSON-RPC stream — never `print(...)` to
> stdout while serving; send logging to **stderr**.

### Claude Code integration

After `mise run install`, register the installed binary (user scope) — or just run `mise run mcp-add`,
which does the same:

```bash
claude mcp add himalaya-mcp -- "$HOME/.local/bin/himalaya-mcp" serve
```

Or use a `.mcp.json` (this repo's is git-ignored, since it holds a machine-specific absolute path):

```json
{
  "mcpServers": {
    "himalaya-mcp": {
      "command": "/Users/you/.local/bin/himalaya-mcp",
      "args": ["serve"],
      "env": { "EXPERIMENTAL_ENABLED": "true" }
    }
  }
}
```

### Claude Desktop integration

**Easiest — let the CLI do it.** After installing the binary, run:

```bash
himalaya-mcp setup            # add/update the himalaya-mcp entry in Claude Desktop's config
himalaya-mcp setup --check    # verify the entry (paths exist & are runnable); non-zero exit if not
himalaya-mcp setup --remove   # remove the entry
```

`setup` writes an entry pointing at the running binary, resolves `himalaya` (via `PATH` /
`$HIMALAYA_BIN_PATH`) and bakes it into the entry's `env` so Claude Desktop — which doesn't inherit
your shell `PATH` — can find it. It merges into the existing config (other servers/preferences are
preserved) and, by default, targets the OS location below (override with `--config <path>`). Restart
Claude Desktop afterward.

**Manual alternative.** Add the server to Claude Desktop's config yourself, then restart it:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "himalaya-mcp": {
      "command": "/Users/you/.local/bin/himalaya-mcp",
      "args": ["serve"],
      "env": {
        "HIMALAYA_BIN_PATH": "/opt/homebrew/bin/himalaya",
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        "HIMALAYA_FOLDER": "INBOX",
        "HIMALAYA_TIMEOUT": "120000",
        "EXPERIMENTAL_ENABLED": "false"
      }
    }
  }
}
```

> **Important:** use **absolute paths** — Claude Desktop is a GUI app and does **not** inherit your
> shell `PATH`, so `himalaya` won't be found unless you set `HIMALAYA_BIN_PATH` (and add its directory
> to `PATH` for its own runtime deps). Merge the `himalaya-mcp` entry into any existing `mcpServers`
> rather than replacing the file. A ready-to-edit copy lives at
> [`examples/claude_desktop_config.json`](examples/claude_desktop_config.json). Set
> `EXPERIMENTAL_ENABLED` to `"true"` only if you want the irreversible `delete_email` tool exposed.

---

## Example prompts

Once the server is connected, drive it with natural language from your MCP host (Claude Code, an
IDE, …). A good archive-and-flag prompt is explicit about **scope**, **action**, and **confirmation**,
since some actions are irreversible:

> **Archive & flag prompt**
>
> Go through my INBOX and help me triage:
> 1. Find every unread email from GitHub notifications (`search_emails` with `from github`).
> 2. Show me the list first — subject, sender, date — and **wait for my confirmation**.
> 3. On my OK, mark them all read (`flag_email` `action: "add"`, `flags: "Seen"`) and archive them
>    (`move_email` `target_folder: "Archive"`).
> 4. For anything that looks important (security, receipts, a real person), **don't touch it** — list
>    those separately so I can decide.

More focused variants you can paste and tweak:

- **Archive a sender:** "Archive all emails from `noreply@setapp.com` — show me the list before moving
  them to `Archive`."
- **Flag for follow-up:** "Flag emails 228 and 15 as `Flagged` and move them to `Labels/[01] Follow Up`."
- **Star = flag:** "Star (flag as `Flagged`) every email from my manager this week."
- **Mark read + archive a label:** "In `Labels/Newsletters`, mark everything as `Seen` and archive it."
- **Clean up, safely:** "Find read newsletters older than 30 days, list them, and after I confirm,
  archive them."

> **Tip:** always ask the assistant to **list matches and wait for confirmation** before archiving,
> flagging, or (especially) deleting — archive/flag are reversible, `delete_email` is not.

### Prompt library

Reusable, named prompts built on the tools above. Invoke one by name with its arguments (e.g.
"run `triage_inbox` with count=20") and the assistant fills in the rest. All are **read-only**
unless you explicitly approve an action.

| Prompt | Arguments | Purpose |
|--------|-----------|---------|
| `triage_inbox` | `count=10` | Classify recent emails: actionable / FYI / skip |
| `summarize_email` | `id`, `folder?` | One-sentence summary + action items for a message |
| `daily_email_digest` | — | Priority-grouped markdown digest of the inbox |
| `draft_reply` | `id`, `tone?`, `instructions?` | Guided reply composition (does not send) |
| `morning_briefing` | `account?` | Morning briefing with urgency classification |
| `inbox_check` | `folder?`, `account?` | Quick inbox status + highlights |

<details>
<summary><code>triage_inbox</code> — Classify emails: actionable / FYI / skip</summary>

> List the latest `{count=10}` emails from my INBOX (`list_emails` with `page_size={count}`). For
> each, classify it as **Actionable** (needs a reply or task), **FYI** (read-only, keep), or **Skip**
> (newsletter/promo/noise). Return a table: id · from · subject · class · one-line reason. Don't move,
> flag, or delete anything — just propose what I could archive/flag, and wait for my go-ahead.

</details>

<details>
<summary><code>summarize_email</code> — One-sentence summary + action items</summary>

> Read email `{id}` (in `{folder=INBOX}`) with `read_email`. Give me: (1) a **one-sentence summary**,
> (2) a bullet list of **action items / requests** directed at me (empty if none), and (3) any
> deadline or date mentioned. Keep it tight — no quoting the whole message.

</details>

<details>
<summary><code>daily_email_digest</code> — Priority-grouped markdown digest</summary>

> Build a markdown digest of my current INBOX (use `list_emails`, and `read_email` only where a
> subject is ambiguous). Group by priority — **🔴 Needs action**, **🟡 Worth a look**, **⚪ FYI /
> noise** — and within each group list `from — subject` (id). End with a 2–3 line "bottom line" of
> what deserves my attention today. Read-only.

</details>

<details>
<summary><code>draft_reply</code> — Guided reply composition</summary>

> Draft a reply to email `{id}` (in `{folder=INBOX}`) using `draft_reply`. Tone: `{tone=friendly and
> concise}`. Extra guidance: `{instructions}`. First show me the original's key points, then the
> proposed reply as a template. **Do not send** — I'll review, and only send via `send_email` with
> `confirm=true` once I approve.

</details>

<details>
<summary><code>morning_briefing</code> — Morning briefing with urgency classification</summary>

> Give me a morning briefing for account `{account=default}`. Pull today's and yesterday's unread mail
> (`search_emails` with a recent-date query), then classify each as **Urgent** (time-sensitive / from a
> person awaiting me), **Today** (handle before EOD), or **Later**. Lead with a one-paragraph summary,
> then the grouped list. Flag anything that looks like a deadline, meeting, or security alert.

</details>

<details>
<summary><code>inbox_check</code> — Quick inbox status + highlights</summary>

> Quick status of `{folder=INBOX}` for account `{account=default}`: how many unread, and the top 5
> most notable messages right now (sender · subject · why it stands out). One short paragraph, no
> table. Read-only.

</details>

---

## Configuration

Settings are read with `swift-configuration`. A `ConfigReader` is resolved once at startup from two
layered providers — **environment variables first** (highest precedence), then an optional **JSON
file**:

| Key | Env var | JSON path | Default |
|-----|---------|-----------|---------|
| `experimental.enabled` | `EXPERIMENTAL_ENABLED` | `experimental.enabled` | `false` |
| Default account | `HIMALAYA_ACCOUNT` | `himalaya.account` | system default |
| Default folder | `HIMALAYA_FOLDER` | `himalaya.folder` | `INBOX` |
| Command timeout (ms) | `HIMALAYA_TIMEOUT` | `himalaya.timeout` | `120000` (2 min; `0` = unlimited) |

Also: `HIMALAYA_BIN_PATH` overrides binary discovery (see [What it does](#what-it-does)).

The config file is `himalaya-mcp.json` in the working directory, or the path in `$HIMALAYA_MCP_CONFIG`. A
missing file is fine; env always wins over the file.

```json
{
  "experimental": { "enabled": true },
  "himalaya": { "account": "work", "folder": "INBOX", "timeout": 120000 }
}
```

`HIMALAYA_ACCOUNT` / `HIMALAYA_FOLDER` are woven into every command as `--account` / `--folder` when a
tool call omits them (folder only for commands that accept one). `HIMALAYA_TIMEOUT` bounds each
subprocess; exceeding it terminates the command and returns a timeout error.

### Experimental features

When `experimental.enabled` is **true**, experimental surfaces are exposed; when false they are
hidden (absent from `--help` / `tools/list`, unknown if invoked). Mark a `ToolHandler` with
`isExperimental: true` (or gate a subcommand behind the flag) to place it behind this switch.

```bash
EXPERIMENTAL_ENABLED=true "$HOME/.local/bin/himalaya-mcp" serve
```

---

## Adding a new feature

The pattern is "write once, expose twice":

1. **Core** — add a `Request` in `Sources/App/Requests/`, resolving services via
   `application.make(...)`.
2. **Register** — if it needs a new service, register it in `configure(_:)` (`Sources/App/Configure.swift`).
3. **CLI** — add a `ParsableCommand` in `Sources/HimalayaMcpCLI/Commands/` that calls
   `execute(input, in: app)`, and register it in the root command's `subcommands`.
4. **MCP** — add a `ToolHandler` in `Sources/HimalayaMcpCLI/MCP/ToolHandler.swift` (set
   `isExperimental: true` to gate it) that calls the same `Request`.

Both surfaces share the new feature with zero duplicated logic.

---

## Tests

```bash
swift test        # or: mise run test
```

Tests are split per module (`AppTests`, `AppConfigurationTests`, `HimalayaMcpCLITests`). Requests are
exercised hermetically by registering a **stub `ExecutableService`** in a container — no real
`swift` shell-out.
