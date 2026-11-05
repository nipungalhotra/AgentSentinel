# Product

<!-- impeccable:product-schema 1 -->

## Platform

web (marketing site). The product itself is a native macOS menu-bar app plus a cross-platform daemon for Windows and Linux.

## Stack

Marketing site: static HTML/CSS/JS in `website/`, deployed to GitHub Pages (from the brief; no framework, no build step).

## Users

Primary: individual developers who run one or more AI coding agents (Claude Code, Codex, Cursor, Antigravity, GitHub Copilot CLI, Claude Desktop) on their own machine and want to see and approve risky actions without babysitting a terminal or granting blanket permissions.

Secondary (mentioned, not targeted first): engineering teams that need shared policy and audit logs for AI agents.

## Product Purpose

loggdin is a permission gate for AI coding agents. Every risky action an agent wants to take (a shell command, a file write, a network call) is held and shown in one place; the developer allows it once, for 10 minutes, always, or denies it. Success: agents keep moving, nothing destructive happens without a human seeing it, and the developer stops copy-pasting approvals between tools.

## Positioning

One gate for every agent on the machine, instead of each tool's own permission prompt. On macOS the request appears as a card dropping out of the MacBook camera notch, with Touch ID for high-risk actions; keyboard focus returns to the editor afterwards. Approvals are scoped (folder, tool family, 10 minutes, always) and hardened against prefix smuggling (`ls && curl … | sh`). On Windows and Linux the same API runs as a small background daemon with a local approval page.

## Operating Context

- Agents call loggdin through hooks (`sentinel-hook`), an MCP server (`sentinel-mcp.js`) or the Python/Node SDKs.
- macOS: menu-bar app `Loggdin.app`, notch/floating-island popup, dashboard, CLI `loggdin`.
- Windows/Linux: `loggdin.py` daemon, approval web page via `loggdin ui`, desktop notifications, installers `install.ps1` / `install.sh`.
- Decisions: Allow once, Allow 10 min, Allow 10 min in all folders (opt-in, never for high risk), Always allow, Deny. Also via CLI, `loggdin://` URLs and Apple Shortcuts.
- Local only: everything runs on 127.0.0.1 / a Unix socket with a per-user token; tamper-evident SHA-256 audit chain; optional webhooks; workspace policy file `.loggdin.json`.

## Capabilities and Constraints

- Supports Claude Code, Codex, Cursor, Claude Desktop (Cowork), Antigravity, GitHub Copilot CLI, ZSH shells, and custom agents via SDKs.
- macOS 14+ universal (Apple silicon and Intel). Windows and Linux need Python 3.9+; Node.js only for the MCP integration.
- The macOS build is not yet Developer ID signed/notarized: no public Mac download at launch. Primary call to action is a waitlist.
- Pricing undecided: Free is available now; Pro and Team are "coming soon" with no prices.
- Waitlist collection service not chosen yet (the page must work without one and be easy to connect).
- Not affiliated with Google, Anthropic, OpenAI, Anysphere, or GitHub; agent names are used only to state compatibility.

## Brand Commitments

- Name: loggdin (lowercase). Formerly "Agent Sentinel"; CLI aliases `loggdin` and `sentinel`.
- App icon and imagery: `assets/AppIcon.icns`, `assets/logo.png`, `assets/notch_card_hero.jpg`.

## Evidence on Hand

- Real product facts and test results in the repo (README.md, tests/). Measured: idle CPU about 0.1%.
- No testimonials, customer logos, download counts, press, or benchmarks exist. Do not fabricate any.

## Product Principles

1. The human sees every risky action; nothing destructive is approved silently.
2. Stay out of the way: one keystroke, focus returns, no terminal babysitting.
3. Local first: no cloud account, no data leaves the machine.
4. Approvals are as narrow as possible by default; broader scopes are explicit opt-ins.
5. Tell the truth about compatibility and status (beta, unsigned, coming soon).
