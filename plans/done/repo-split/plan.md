# Repo Split Migration Plan — v2

Split `plans/project/somewm-one` and `plans/project/somewm-shell` out of the
`raven2cz/somewm` fork into their own GitHub repositories, keeping the fork
as a working tree for upstream PRs.

**Status:** v2 EXECUTING — Step 1 (cleanup commit `5f62fae`) and Step 2
(subtree split: `export/somewm-one`, `export/somewm-shell`) DONE. v1
preserved as `plan-v1-rejected.md`.

**v1 → v2 changes (Codex review summary + user direction)**

1. **Visibility: public from the start** (per user, restoring v1 decision
   after a brief private-first detour). Operational detail in history is
   user-accepted; secret/token scan came back clean.
2. **Step 6 "Path-decoupling"** added with full audit table: live runtime
   refs to monorepo paths exist in `rc.lua:278`, `MemoryDetail.qml:574`,
   `tests/test-all.sh`, `IPC.md`, docs. These break standalone use unless
   fixed.
3. **Step 7 "Codex re-review of path-decoupling"** added per user: after
   the fixes are committed to new repos, pipe diff into Codex for a
   second-pass review before deploy.
4. "Preserve full history" claim softened. `git subtree split` preserves
   commits that touched the prefix; it rewrites commit IDs and does **not**
   carry tags, signatures, PR metadata.
5. `somewm-shell` deploy now backs up `~/.config/quickshell/somewm` before
   rsync. v1 missed this.
6. Fork-cleanup commit and doc rewrites merged into one commit so fork is
   never published pointing at deleted paths.
7. Dirty-tree inventory refreshed (Step 1 already executed).

## Goals

1. **De-promote the fork.** Public viewers (Reddit, YouTube, GitHub visitors)
   land on `trip-zip/somewm` + `somewm.org`, not the fork.
2. **Make user-facing projects standalone.** `somewm-one` and `somewm-shell`
   become first-class GitHub projects under `raven2cz/`.
3. **Preserve commit history that touched each prefix.** `git subtree split`
   keeps author/date/message for every commit that modified
   `plans/project/somewm-{one,shell}/**`. It does **not** preserve commit
   IDs, signatures, tags, or PR/review metadata. Files that lived elsewhere
   before being moved into `plans/project/...` will lose pre-move ancestry.
4. **Zero regression for daily workflow.** Deploy, reload, sandbox, memory
   diagnostics work identically after split — three working dirs instead of
   one.

## Out of scope

- Compositor `main` re-baseline against upstream. Separate cleanup pass.

## Pre-split cleanup (done 2026-04-29 before Step 0)

- `plans/project/somewm-one/themes/default/wallpapers/8.png` → converted to
  `8.jpg` (q90, matching 9.jpg) and removed. All wallpapers now `.jpg`.
- `plans/docs/youtube-trailer-description.md` — deleted (per Q2).
- `plans/project/somewm-shell-ai/` — deleted (per Q3, was deferred in v1).

## Pre-flight inventory (refreshed 2026-04-29)

| Item | Value |
|---|---|
| Fork on disk | `~/git/github/somewm` (207 M, .git=45 M) |
| somewm-one tree | 20 M (mostly wallpapers); ~35 commits after subtree split |
| somewm-shell tree | 1.4 M; ~25 commits after subtree split |
| somewm-shell-ai tree | 48 K (deferred) |
| Working tree dirty files (verified) | `plans/project/somewm-one/themes/default/wallpapers/{3.jpg,6.jpg,9.jpg}` modified, `8.jpg` deleted, `8.png` untracked, `plans/docs/youtube-trailer-description.md` untracked, `plans/repo-split/` untracked |
| Backup | `~/git-backups/somewm-pre-split-20260429-084301/` (mirror + tar 55 M) |
| Subtree-split smoke test | OK — extracted branches have clean trees + own deploy.sh |
| Token/key scan | clean — no auth tokens, API keys, env secrets in tree |
| Operational detail in tree | `/home/box` hardcoded paths, Synology autostart entry, hardware references in CLAUDE.md (NVIDIA RTX 5070 Ti). User-acceptable disclosure — not secret, but worth conscious accept. |

## Decisions (locked)

| # | Question | Decision |
|---|---|---|
| 1 | History | **Preserve commits that touched prefix** via `git subtree split`. Commit IDs are rewritten; tags/signatures/PR-metadata not carried. |
| 2 | New repo visibility | **Public at creation.** README leads with upstream `trip-zip/somewm` + `somewm.org`. Operational detail in history is user-accepted; secret scan clean. |
| 3 | Scripts (`install-scenefx.sh`, `start.sh`, `somewm-sandbox.sh`, memory snapshot/trend) | Stay in fork under `plans/scripts/`. Each project repo carries only its own `deploy.sh`. |
| 4 | LICENSE in new repos | **MIT** in both `somewm-one` and `somewm-shell` (treated as library-style code). |
| 5 | History audit findings | **Accept** as-is. Hardcoded `/home/box`, Synology autostart, hardware refs are operational detail, not secrets. No `git filter-repo` pass. |
| 6 | Topic tags on new repos | **Yes** at public flip: `wayland`, `awesomewm`, `quickshell`, `lua`, `desktop-shell`. |
| 7 | Subtree-split limits | **Accept**. New commit IDs, no tags/signatures/PR-metadata carry-over. Spot check confirmed no renames into the prefix — both projects are first-class under `plans/project/...` since the kolo6 replay. |

## Path coupling — full audit

These references must be addressed before each project repo can stand alone.
Severity:
- **RUNTIME** — feature breaks at runtime if path is wrong
- **TEST** — test scripts break, runtime unaffected
- **DOC** — only documentation is wrong; safe but noisy

**Audit run 2026-04-29 — exhaustive grep of all `*.lua`, `*.qml`, `*.sh`,
`*.md`, `*.json` files in both prefixes for `plans/project`,
`plans/scripts`, `plans/docs`, `git/github/somewm`.**

### somewm-one

| File | Line | Severity | Current | Fix |
|---|---|---|---|---|
| `rc.lua` | 278 | 🔴 RUNTIME | spawn `os.getenv("HOME") .. "/git/github/somewm/plans/project/somewm-shell/theme-export.sh"` | `os.getenv("HOME") .. "/git/github/somewm-shell/theme-export.sh"` |
| `rc.lua` | 8 | 🟡 DOC comment | "See plans/project/somewm-one/ for the full tree." | "See this repo for the full tree." |
| `deploy.sh` | ~33 | 🟡 RUNTIME (graceful) | `SNAPSHOT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/somewm-snapshot.sh"` | `SNAPSHOT_SCRIPT="${SOMEWM_FORK_PATH:-$HOME/git/github/somewm}/plans/scripts/somewm-snapshot.sh"` (already `if [[ -x ]]` guarded — silently skips if missing) |
| `deploy.sh` | 6 | 🟡 DOC | comment mentions `plans/project/somewm-one/` | strip `plans/project/` |
| `spec/portraits_spec.lua` | 5 | 🟢 TEST | `package.path = "./plans/project/somewm-one/?.lua;" ..` | `"./?.lua;./?/init.lua;" ..` |
| `spec/exit_screen_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/autostart_spec.lua` | 9 | 🟢 TEST | same pattern | same fix |
| `spec/broker_spec.lua` | 6 | 🟢 TEST | same pattern | same fix |
| `spec/service_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/factory_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/test_exit_screen_theme.lua` | 7 | 🟢 TEST | same pattern | same fix |
| `spec/services_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/wallpaper_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/themes_spec.lua` | 5 | 🟢 TEST | same pattern | same fix |
| `spec/animations_spec.lua` | 2-4 | 🟢 TEST (header comment) | busted invocation comment | strip `plans/project/somewm-one/` |
| `spec/autostart_spec.lua` | 4-6 | 🟢 TEST (header comment) | busted invocation comment | strip `plans/project/somewm-one/` |
| `README.md` | 97, 102 | 🟢 DOC | `plans/project/somewm-one/`, `plans/scripts/check-headers.sh` | strip prefix; check-headers → `~/git/github/somewm/plans/scripts/check-headers.sh` |
| `GUIDE.md` | 232, 235, 241, 247, 357, 426 | 🟢 DOC | `plans/project/somewm-one/...` | strip prefix |
| `GUIDE.md` | 439 | 🟢 DOC | `plans/scripts/check-headers.sh` | `~/git/github/somewm/plans/scripts/check-headers.sh` |
| `STYLE.md` | 117 | 🟢 DOC | `plans/scripts/check-headers.sh` | same fix |

### somewm-shell

| File | Line | Severity | Current | Fix |
|---|---|---|---|---|
| `services/MemoryDetail.qml` | 574 | 🔴 RUNTIME | `var script = home + "/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh"` | `var fork = Quickshell.env("SOMEWM_FORK_PATH") \|\| (home + "/git/github/somewm"); var script = fork + "/plans/scripts/somewm-memory-snapshot.sh"` — keep `if (FileSystem.exists)` guard or just let `execDetached` no-op silently |
| `services/MemoryDetail.qml` | 583 | 🔴 RUNTIME | xdg-open `home + "/git/github/somewm/plans/docs/memory-baseline.md"` | same env-var pattern |
| `services/MemoryDetail.qml` | 14 | 🟡 DOC comment | mention | update path |
| `modules/memory-detail/TrendSection.qml` | 197 | 🟡 UI text | "See `plans/scripts/somewm-memory-trend.sh` for long traces." | "See `~/git/github/somewm/plans/scripts/somewm-memory-trend.sh`" |
| `modules/memory-detail/SomewmInternalsSection.qml` | 154 | 🟡 UI text | "See plans/docs/memory-baseline.md." | "See `~/git/github/somewm/plans/docs/memory-baseline.md`" |
| `tests/test-all.sh` | 385 | 🟢 TEST | `theme_export="/home/box/git/github/somewm/plans/project/somewm-shell/theme-export.sh"` | `theme_export="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/theme-export.sh"` (same repo) |
| `tests/test-all.sh` | 583 | 🟢 TEST | `RC_LUA="/home/box/git/github/somewm/plans/project/somewm-one/rc.lua"` | `RC_LUA="${SOMEWM_ONE_PATH:-$HOME/git/github/somewm-one}/rc.lua"` |
| `tests/test-all.sh` | 1487 | 🟢 TEST | `ONE_DIR="/home/box/git/github/somewm/plans/project/somewm-one"` | `ONE_DIR="${SOMEWM_ONE_PATH:-$HOME/git/github/somewm-one}"` |
| `IPC.md` | 43-46 | 🟢 DOC | `plans/project/somewm-one/fishlive/...` | `~/git/github/somewm-one/fishlive/...` |
| `STYLE.md` | 119 | 🟢 DOC | `plans/scripts/check-headers.sh` | `~/git/github/somewm/plans/scripts/check-headers.sh` |
| `README.md` | 134 | 🟢 DOC | `plans/project/somewm-shell/` | strip prefix |
| `GUIDE.md` | 311, 541, 542, 545, 551, 554, 583, 586, 772, 920, 923, 926, 929, 935 | 🟢 DOC | `plans/project/somewm-shell/...` | strip prefix |
| `GUIDE.md` | 854 | 🟢 DOC | `plans/project/somewm-one/rc.lua` | `~/git/github/somewm-one/rc.lua` |

**Files audited and confirmed clean (no changes needed):** `theme-export.sh`,
`*.json`, `core/*.qml`, `components/*.qml`, all other `modules/` directories.

**Apply order:** fixes commit onto each cloned new repo's `main` (Step 6),
not onto the fork. Fork's `plans/project/...` paths stay until Step 9
cleanup.

## Migration playbook

Each step is independently reversible up to **Step 9**. Step 9 is the
destructive moment (fork-side `git rm` + push). Everything before that can
be undone with `gh repo delete --yes` and `git branch -D`.

### Step 0 — Prerequisites (no changes)

```bash
gh auth status                                                    # raven2cz
gh api user --jq '.login'                                         # → "raven2cz"
git -C /home/box/git/github/somewm status --short                 # capture state
ls /home/box/git-backups/somewm-pre-split-20260429-084301/        # backup exists
test -d /home/box/git/github/somewm-one  || echo "OK: no clash"   # target dirs free
test -d /home/box/git/github/somewm-shell || echo "OK: no clash"
gh repo view raven2cz/somewm-one  2>/dev/null && echo "WARN: name taken"
gh repo view raven2cz/somewm-shell 2>/dev/null && echo "WARN: name taken"
```

### Step 1 — Commit pre-split cleanup to fork main (per Q1)

The fork must be **fully committed** to `main` before subtree split. Per
user direction, we commit (not stash) the wallpaper changes and the
deletions of `youtube-trailer-description.md` + `somewm-shell-ai/`.

```bash
cd /home/box/git/github/somewm

# Stage cleanup + plan
git add plans/project/somewm-one/themes/default/wallpapers/
git add plans/project/somewm-shell-ai/    # captures all D entries
git add plans/docs/youtube-trailer-description.md   # captures D
git add plans/repo-split/

git status --short
git diff --staged --stat | head -20

git commit -m "$(cat <<'EOF'
chore: pre-split cleanup — normalize wallpapers + drop unfinished pieces

Wallpapers: convert 8.png to 8.jpg (q90) so the wallpapers/ dir is
homogeneous .jpg. Update 3/6/9.jpg to current set.

Drop plans/project/somewm-shell-ai/ — small, unfinished, not part of
the upcoming standalone repo split.

Drop plans/docs/youtube-trailer-description.md — superseded by the
trailer copy already published.

Add plans/repo-split/ — migration plan + Codex review trail.
EOF
)"
git push origin main
```

After this commit, `git status --short` is clean. Subtree split will
include the cleaned tree and the new wallpaper.

### Step 2 — Run the subtree split

```bash
cd /home/box/git/github/somewm
git checkout main
git pull --ff-only origin main

git subtree split --prefix=plans/project/somewm-one   -b export/somewm-one
git subtree split --prefix=plans/project/somewm-shell -b export/somewm-shell

git log --oneline export/somewm-one   | wc -l       # expect ~35
git log --oneline export/somewm-shell | wc -l       # expect ~25
git ls-tree --name-only export/somewm-one  | head
git ls-tree --name-only export/somewm-shell | head
```

The `export/*` branches stay local — paper trail. Not pushed to fork.

### Step 3 — Create new GitHub repos as **PUBLIC**

```bash
gh repo create raven2cz/somewm-one \
    --public \
    --description "AwesomeWM-style rc.lua + themes for SomeWM" \
    --homepage "https://somewm.org"

gh repo create raven2cz/somewm-shell \
    --public \
    --description "Quickshell-based desktop shell for SomeWM" \
    --homepage "https://somewm.org"
```

### Step 4 — Push split branches as `main`

```bash
cd /home/box/git/github/somewm
git push git@github.com:raven2cz/somewm-one.git   export/somewm-one:main
git push git@github.com:raven2cz/somewm-shell.git export/somewm-shell:main
```

### Step 5 — Clone new repos into `~/git/github/`

```bash
cd /home/box/git/github
git clone git@github.com:raven2cz/somewm-one.git
git clone git@github.com:raven2cz/somewm-shell.git
ls /home/box/git/github/somewm-one/deploy.sh
ls /home/box/git/github/somewm-shell/deploy.sh
```

### Step 6 — Patch each new repo (path-decoupling + bootstrap + LICENSE)

License (per Q4): MIT in both repos.

```bash
# Generate MIT LICENSE in each new repo
for r in somewm-one somewm-shell; do
  cat > /home/box/git/github/$r/LICENSE <<'EOF'
MIT License

Copyright (c) 2026 Antonin Fischer (raven2cz)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
done
```

Apply the fixes from the **Path coupling** table above. Both repos in
parallel.

For `somewm-one`:
```bash
cd /home/box/git/github/somewm-one
# 1. Fix rc.lua:278 — strip "plans/project/somewm-shell" + retain $HOME
sed -i 's|/git/github/somewm/plans/project/somewm-shell/|/git/github/somewm-shell/|' rc.lua

# 2. Fix spec/*.lua package.path lines (busted is run from repo root now)
sed -i 's|"./plans/project/somewm-one/|"./|g; s|;./plans/project/somewm-one/|;./|g' spec/*.lua

# 3. README/GUIDE/STYLE docs — strip plans/project/somewm-one/ prefix
sed -i 's|plans/project/somewm-one/||g' README.md GUIDE.md STYLE.md deploy.sh

# 4. .gitignore — copy from fork-side ignores
cat > .gitignore <<'EOF'
.active_theme
.default_portrait
rc.lua.bak
themes/*/user-wallpapers/
EOF

# 5. CLAUDE.md — short pointer to fork
cat > CLAUDE.md <<'EOF'
# somewm-one — Claude Code Hint

This is the rc.lua + themes I run on top of SomeWM. Compositor source,
build/install scripts, and IPC primitives live in the SomeWM fork at
`~/git/github/somewm` (CLAUDE.md there has full conventions).

Workflow:
- Edit here, then run `./deploy.sh`.
- After deploy, `somewm-client reload` to pick up changes.
EOF

# 6. README header — lead with upstream
# (manual edit — prepend a paragraph that says: "compositor is upstream
#  trip-zip/somewm + somewm.org. This repo is just my config layer.")

git add -A
git diff --staged --stat
git commit -m "chore: standalone repo bootstrap (path-decoupling, .gitignore, CLAUDE.md)"
git push origin main
```

For `somewm-shell`:
```bash
cd /home/box/git/github/somewm-shell

# 1. services/MemoryDetail.qml — env-var lookup with fallback
#    (manual edit — pattern: 
#     var fork = Quickshell.env("SOMEWM_FORK_PATH") || home + "/git/github/somewm"
#     var script = fork + "/plans/scripts/somewm-memory-snapshot.sh"
#     if (!FileSystem.exists(script)) { console.warn(...); return })
#    Apply same fix at line 583 for memory-baseline.md.

# 2. tests/test-all.sh — relative + env-var paths
#    Manual edits at lines 385, 583, 1487. test-all.sh is run from repo root,
#    so use $(dirname "${BASH_SOURCE[0]}")/.. for shell-internal references.

# 3. IPC.md — replace plans/project/somewm-one/ with ~/git/github/somewm-one/
sed -i 's|plans/project/somewm-one/|~/git/github/somewm-one/|g' IPC.md

# 4. README/GUIDE/STYLE — strip plans/project/somewm-shell/
sed -i 's|plans/project/somewm-shell/||g' README.md GUIDE.md STYLE.md

# 5. .gitignore + CLAUDE.md analogous to somewm-one
cat > .gitignore <<'EOF'
*.qmlc
*.jsc
EOF

cat > CLAUDE.md <<'EOF'
# somewm-shell — Claude Code Hint

Quickshell desktop shell for SomeWM. Compositor lives in the SomeWM fork
at `~/git/github/somewm`; the rc.lua that talks to this shell lives at
`~/git/github/somewm-one`.

Workflow:
- Edit QML here, then run `./deploy.sh`.
- After deploy, restart Quickshell:
  `pkill -f 'qs -c somewm'; qs -c somewm -n -d &`
EOF

# 6. README — upstream-first lead paragraph (manual)

git add -A
git diff --staged --stat
git commit -m "chore: standalone repo bootstrap (path-decoupling, .gitignore, CLAUDE.md)"
git push origin main
```

### Step 7 — Codex re-review of path-decoupling diff

Per user direction: after Step 6 commits the path fixes to both new repos,
pipe the diff into Codex for a second-pass review. Goal: catch anything
we missed in the audit, verify the env-var fallback patterns are sane,
verify nothing broke that the audit didn't anticipate.

```bash
cd /home/box/git/github
{
  echo "=== somewm-one path-decoupling diff ==="
  git -C somewm-one log -1 --format='%H %s' main
  git -C somewm-one diff main~1 main
  echo ""
  echo "=== somewm-shell path-decoupling diff ==="
  git -C somewm-shell log -1 --format='%H %s' main
  git -C somewm-shell diff main~1 main
} | codex exec -m gpt-5.4 --full-auto \
    "Review this path-decoupling diff. Two repos (somewm-one, somewm-shell) just split out of a monorepo. Check: (1) any hardcoded path I missed; (2) env-var fallback patterns are robust (graceful when fork dir is absent); (3) test scripts still work standalone; (4) no doc still claims the old path; (5) nothing else broke. Be blunt about gaps."
```

Apply Codex feedback as additional commits on each new repo's `main`
before Step 8.

### Step 8 — Smoke test

Critical: back up live deploy targets first.

```bash
TS=$(date +%Y%m%d-%H%M%S)
cp -r ~/.config/somewm           ~/.config/somewm.bak.$TS         # full snapshot
cp -r ~/.config/quickshell/somewm ~/.config/quickshell/somewm.bak.$TS

# Dry runs
~/git/github/somewm-one/deploy.sh   --dry-run
~/git/github/somewm-shell/deploy.sh --dry-run

# Real deploys
~/git/github/somewm-one/deploy.sh
~/git/github/somewm-shell/deploy.sh

# Reload + sanity
somewm-client reload
somewm-client eval 'return awesome.version'
pkill -f 'qs -c somewm'; qs -c somewm -n -d &
sleep 2
somewm-client eval 'return #client.get()'   # IPC + Lua alive
```

User-driven visual check: tag switch (sliding + wallpaper), Dolphin opens
with correct fonts, control panel toggles, notification fires, MemoryDetail
copy button (validates the env-var fallback in Step 6).

If anything fails, restore from `*.bak.$TS` and abort. Repos stay private.

### Step 9 — Add topics + fork cleanup (destructive)

Repos are already public from Step 3. This step adds topic tags and
removes the now-obsolete `plans/project/somewm-{one,shell}/` from the fork.

```bash
# Topic tags (per Decision #6)
gh repo edit raven2cz/somewm-one   \
    --add-topic wayland --add-topic awesomewm --add-topic lua --add-topic somewm
gh repo edit raven2cz/somewm-shell \
    --add-topic wayland --add-topic quickshell --add-topic qml --add-topic desktop-shell --add-topic somewm

# 2. Fork: remove + doc rewrite in ONE commit so fork is never published
#    pointing at deleted dirs.
cd /home/box/git/github/somewm
git checkout main
git rm -r plans/project/somewm-one
git rm -r plans/project/somewm-shell
# somewm-shell-ai stays — see "Out of scope".

# Edit CLAUDE.md + AGENTS.md sections that reference old paths.
# Manual edits — sections to rewrite:
#   * "User Configuration"
#   * "somewm-one (User Config Project)"
#   * "Plans Directory"
# Replace with: "Config + shell live in sibling repos:
#   ~/git/github/somewm-one  (raven2cz/somewm-one)
#   ~/git/github/somewm-shell (raven2cz/somewm-shell)
#  This fork keeps fork-only scripts (install-scenefx.sh, start.sh,
#  somewm-sandbox.sh, somewm-memory-*.sh) and is used as a working tree
#  for upstream PRs to trip-zip/somewm."

git add CLAUDE.md AGENTS.md
git diff --staged | head -100      # eyeball before commit

git commit -m "$(cat <<'EOF'
chore: split somewm-one and somewm-shell into standalone repos

Both projects now live at:
  - https://github.com/raven2cz/somewm-one
  - https://github.com/raven2cz/somewm-shell

The fork goes back to being a working tree for upstream PRs to
trip-zip/somewm. Users should install upstream from somewm.org.

History was preserved via `git subtree split` before deletion;
the export/* branches remain locally as a paper trail.
EOF
)"
git push origin main
```

### Step 10 — Update auto-memory + external copy

No stash to restore (Step 1 committed everything). Just sweep:

- Auto-memory entries that mention `plans/project/somewm-{one,shell}`:
  `feedback_qs_deploy.md`, `feedback_deploy_automaticky.md`,
  `feedback_never_deploy_live.md`, `project_multimonitor_samsung.md`.
  Update paths to `~/git/github/somewm-{one,shell}/`.

## Rollback

| Failure point | Rollback |
|---|---|
| Step 2 (subtree split errored) | `git branch -D export/somewm-{one,shell}`. Fork untouched. |
| Step 4 (push failed) | `gh repo delete raven2cz/somewm-{one,shell} --yes`. Fork untouched. |
| Step 6 (path-decoupling broke something) | Force-push corrected `main` to private repo, or `gh repo delete --yes` and redo from Step 3. |
| Step 7 (history audit found unwanted detail) | `git filter-repo` on private repo, force-push. Optionally redo from Step 3 with prepared filter rules. Repos still private — no leak. |
| Step 8 (smoke test failed) | Restore `~/.config/somewm.bak.$TS` and `~/.config/quickshell/somewm.bak.$TS`, `gh repo delete --yes`, fix path-decoupling, redo from Step 5. |
| Step 9 (after public flip) | `gh repo edit --visibility private` (caches/forks may persist). For unwanted history disclosure, treat as leaked: rotate anything sensitive, accept the leak otherwise. |
| Step 9 (after fork push) | `git revert <split-cleanup-commit>`, `git push origin main`. Fork is restored. New public repos remain. |
| Catastrophic | Restore from `~/git-backups/somewm-pre-split-20260429-084301/somewm.git` mirror — force-push fork main. Loses any commits made between split and restore. |

## Risks and mitigations

1. **Coupled runtime paths** (highest risk). Documented and fixed in Step 6.
   Verified by smoke test in Step 8 before public flip.
2. **History rewrite drops commit IDs.** Anyone who linked to a fork commit
   touching `plans/project/...` will see those links break for the new
   repos. The fork's own commits keep their IDs (we don't rewrite the
   fork's history). Acceptable.
3. **Operational detail in extracted history.** Hardware refs, hostnames,
   `/home/box` paths. Audit in Step 7. User-acceptable disclosure or
   `git filter-repo` pre-public-flip.
4. **Public-flip is one-way for indexers.** GitHub caches, third-party
   mirrors, and search engines may have copied content during the brief
   public window. Plan keeps "private until smoke test passes" exactly to
   minimize this window.
5. **Auto-memory drift.** Several memory entries reference
   `plans/project/...`. Step 11 cleans them up — until then, future
   sessions may follow stale paths. Mitigation: do the cleanup the same day
   as Step 9.
6. **Cross-repo IPC drift.** Compositor signals consumed by `somewm-shell`
   need coordinated commits across two repos. No tooling enforces this;
   `IPC.md` is the contract. Acceptable for two-person scope.

## Open questions

All resolved 2026-04-29 — see Decisions table above. Plan is ready to
execute pending user "go" on Step 1.
