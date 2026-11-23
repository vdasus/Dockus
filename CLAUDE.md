# Dockus

macOS menu bar utility for personal use that brings Windows taskbar behavior to the Dock: clicking the Dock icon of the
active application minimizes its windows, and clicking it again restores them.

## Build, test, run

Builds and tests run on GitHub Actions (`.github/workflows/build.yml`, `macos-15`) on every push to `main`, on pull
requests and on tags `v*`. No macOS development tools are needed on the target Mac.

Local build on a Mac with Xcode (the universal build needs Xcode, not only the Command Line Tools):

```bash
./build.sh   # produces build/Dockus.app and build/Dockus.zip
```

End-to-end test: `Tests/e2e.sh` (CI runner only; it writes to the system TCC database and needs SIP disabled).

Debug log:

```bash
open --env DOCKUS_DEBUG=1 --stderr /tmp/dockus.log /Applications/Dockus.app
```

Release: `git tag v1.0.0 && git push origin v1.0.0`. Installation: see [README](README.md#installation).

## Environment

- **Runtime / SDK**: Swift 5.7 tools (`Package.swift`), AppKit, deployment target macOS 12; universal binary (arm64, x86_64)
- **Tools**: Xcode, `swift`, `sips`, `iconutil`, `codesign`, `lipo`, `otool`, `ditto` (all called by `build.sh`)
- **Services**: none at runtime (no network access). CI: GitHub Actions macOS runners; releases on github.com/vdasus/Dockus
- **Configuration**: `DOCKUS_DEBUG` environment variable (debug log to stderr); `Info.plist` (`__VERSION__` replaced from the `VERSION` variable in `build.sh`); the Enabled setting persists in user defaults; Launch at Login writes `~/Library/LaunchAgents/io.github.vdasus.Dockus.plist`; instance lock at `~/Library/Application Support/<bundle id>/instance.lock`. No secrets
- **Deploy target**: user's Mac, `Dockus.app` in `/Applications` from GitHub Releases; see [README](README.md#installation)

## Project wiki

This repo keeps its own small wiki so that a fresh session can continue without the old chat.
Read this section first; follow it without being asked.

| File | Holds |
|------|-------|
| `CLAUDE.md` (this file) | What the project is, how to build, test and run it, environment, this section |
| `docs/DECISIONS.md` | Decisions that shape the code: what, why, date. Newest last |
| `docs/GOTCHAS.md` | Traps already hit: symptom, cause, fix. One entry per trap |
| `docs/<yyyy-mm-dd>-handoff-<slug>.md` | State for the next session. Only the newest one is current |
| `temp/` (repo root, always git-ignored) | Unresolved sensitive matters: open security holes, exploitable bugs, incident details. Never committed |

At the start of a session: if a `docs/*-handoff-*.md` exists, read the newest one before anything else,
then every file in `temp/`.

### Commands

Each command also works as a phrase. The slash commands are in `.claude/commands/`.

| Command | Also said as | Do |
|---------|--------------|----|
| `/handoff` | `/dev-wiki stash`, "подготовься к запуску с пустым контекстом", "prepare for a fresh session" | First do `/decisions` and `/gotcha` for this session, and `/env` if build files, services or settings changed. Then write `docs/<yyyy-mm-dd>-handoff-<slug>.md`: **Goal**, **State** (done, file paths, branch, last commit), **Decisions** (agreed in this session, with why; link to `docs/DECISIONS.md`), **Dead ends** (tried, failed, why), **Next steps** (numbered; the first one concrete enough to start at once). Delete older handoff files. Anything unresolved and sensitive goes to `temp/<yyyy-mm-dd>-<slug>.md` with the same headings, not to the handoff; the handoff does not mention it. Reply with the path and the line `Read <path> and continue from Next steps.` |
| `/decisions` | "запиши важные решения", "record the decisions" | Add every decision of this session that is not in `docs/DECISIONS.md` yet |
| `/gotcha [what]` | "сохрани gotcha", "запомни грабли", "save this gotcha" | Add the trap to `docs/GOTCHAS.md`; no argument: the last trap hit in this session |
| `/env` | "обнови окружение", "update the environment" | Update **Environment** in this file from the repo (SDKs, tools, services, config) |
| "продолжай" | "continue", "дальше" — in a session that has not done any work yet | Read the newest handoff and the files it points to; compare its **State** with `git status` and `git log -1` and say in one line what differs. Then start on **Next steps** from the first one not done. No handoff: say so and ask what to do |

Without being asked, at the end of a task: a non-obvious fix after debugging → add a gotcha;
a design choice the user made or confirmed → add a decision. Say so in one line.

### Entry formats

```markdown
## <yyyy-mm-dd> <Decision in a few words>

<What was decided.> **Why:** <reason, constraint, rejected alternative.>
```

```markdown
## <Symptom as seen: error text, wrong behaviour>

**Cause:** <why it happens.> **Fix:** <what to do; command or code verbatim.>
```

### Rules

- Generated files in English, neutral register; chat in the user's language.
- No secrets in any file: name the setting and where it lives, never its value.
- `docs/` holds only what is safe to publish. An open security hole, an exploitable bug or an
  incident in progress goes to `temp/`, never to `docs/`, a commit message or `CLAUDE.md`, not even
  as "security issue, being fixed". Before writing to `temp/`, check `git check-ignore -q temp/`;
  not ignored: add `/temp/` to `.gitignore` first. Once fixed, move to `docs/` only what is safe to
  publish (for example a gotcha without the exploit), then delete the `temp/` file.
- Link, don't copy: the README, `docs/DECISIONS.md` and the code are the sources; a handoff points to them.
- Keep `CLAUDE.md` short: details belong in `docs/`.
