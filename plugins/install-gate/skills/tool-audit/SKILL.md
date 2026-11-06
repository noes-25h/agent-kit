---
name: tool-audit
description: "Audit an external tool (CLI, MCP server, plugin, or a package installed machine-wide) before it is installed, and write the audit record that install-gate looks for. Use when the user wants to install a tool, asks whether a tool is safe to install, or when install-gate blocked an install because no record exists. Do not use for changing the settings of a tool that is already installed."
model: inherit
effort: high
---

# Audit a tool before installing it

install-gate blocks a machine-wide install when the project has no audit record for the tool. This skill does the audit and writes that record.

The gate only checks that a record with the right name exists and carries one risk line. It cannot check whether the eight items below were actually looked into. That part depends on this procedure being followed in full.

## Steps

1. Look into all eight items in the table. Do not skip any, even when running unattended. Use primary sources: the tool's own repository, its documentation, the vendor's terms. If something cannot be found, write "not found" in the record. Do not guess.
2. Write the record to `docs/tool-audits/<tool-name>-audit.md`, using the template below. A date prefix (`YYYY-MM-DD_`) in front of the name is allowed.
3. Decide the risk and write it on exactly one line: `Risk: LOW`, `Risk: MID`, or `Risk: HIGH`.
4. If the risk is MID or HIGH, stop and tell the user what was found. Install only after the user has read the record and approved. The gate will also prompt the user at install time.
5. Run the install.
6. Right after installing, apply the mitigations listed in the record (narrow token scopes, separate accounts, disable when not in use).

## Naming the record

The gate compares names exactly, so the file name must be the name used in the install command.

- Lowercase the name. Replace `/`, `@`, and `:` with `-`.
- A Homebrew formula from a tap keeps the tap: `user/tap/name` becomes `user-tap-name-audit.md`.
- A scoped npm package keeps the scope: `@scope/pkg` becomes `scope-pkg-audit.md`.
- A Claude Code plugin keeps the marketplace: `name@marketplace` becomes `name-marketplace-audit.md`.
- An MCP server added with `claude mcp add` uses the server name given on the command line.
- One record per tool. A record that covers two tools under one name does not match either of them.

## The eight items

| # | Item | What to check |
|---|---|---|
| 1 | Origin / publisher | Official vendor, or an individual developer who can be traced (for example on GitHub). An anonymous publisher means do not install. Being listed in a marketplace or registry is where a candidate comes from; it is not a reason to trust it more. |
| 2 | License | MIT, Apache, GPL, and so on. Proprietary or unknown needs the user's approval. |
| 3 | Authentication and where tokens are stored | OAuth, API key, cookie extraction, or plain-text password. Where the token is stored and the file permissions on it. |
| 4 | The publisher's own stance | States "use at your own risk", states that production use is supported, or says nothing. An explicit "at your own risk" means MID or higher. |
| 5 | Internal API or official API | An undocumented internal API can change without notice. If the tool relies on one, say so and note that it needs rechecking periodically. |
| 6 | Terms of service | What the vendor's terms say about automation. A grey area means HIGH and needs the user's approval. |
| 7 | Security audit | Whether a third-party security audit exists. None means MID or higher. |
| 8 | Reversibility | Can it be removed afterwards. Is there an official uninstall procedure. What is left behind (settings, keys, scheduled jobs, login items). Does it update itself. |

## Risk levels

- LOW: official publisher, and nothing in the eight items raises a concern.
- MID: individual open-source publisher, or an explicit "at your own risk", or no security audit.
- HIGH: anonymous publisher, a terms-of-service grey area, or anything that could not be verified and matters.

When two levels apply, use the higher one.

## Record template

```markdown
# <tool-name> install audit

Risk: <LOW | MID | HIGH>

Reason in one line:

| # | Item | Finding | Source |
|---|---|---|---|
| 1 | Origin / publisher | | |
| 2 | License | | |
| 3 | Authentication and token storage | | |
| 4 | Publisher's stance | | |
| 5 | Internal API or official API | | |
| 6 | Terms of service | | |
| 7 | Security audit | | |
| 8 | Reversibility | | |

## Mitigations to apply right after installing

## Decision and grounds

Audited on: <YYYY-MM-DD>
Install command: 
```

Replace the whole `Risk:` line with one value. The template line as written is not accepted by the gate.

## Do not

- Do not write the record after installing and treat it as if the audit had come first.
- Do not keep a tool only because it is already installed. If it is not used, uninstall it.
- Do not mark a tool LOW in order to get past the gate. The record is for the user to read later.
