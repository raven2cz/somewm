# Repo Split Migration Plan

Split `plans/project/somewm-one` and `plans/project/somewm-shell` out of the
`raven2cz/somewm` fork into their own public GitHub repositories, while
keeping the fork as a private-style upstream-PR workspace and preserving
full commit history.

**Status:** DRAFT — awaiting Codex review and user approval before any
destructive operation.

## Goals

1. **De-promote the fork.** Stop pointing public viewers (Reddit, YouTube, GitHub
   visitors) at `raven2cz/somewm`. The canonical install target is
   `trip-zip/somewm` + `somewm.org`.
2. **Make the user-facing projects standalone.** `somewm-one` (config) and
   `somewm-shell` (Quickshell desktop shell) become first-class GitHub
   projects under `raven2cz/`, each with their own README, issues, releases.
3. **Preserve history.** Use `git subtree split` so every existing commit on
   `plans/project/somewm-one/**` and `plans/project/somewm-shell/**` keeps its
   author, date, and message.
4. **Zero regression for daily workflow.** Deploy, reload, sandbox, and memory
   diagnostics must work identically after the split, only with three working
   directories instead of one.

## Out of scope (decided separately later)

- `plans/project/somewm-shell-ai/` — 48 K, six files, unclear status. Keep in
  fork for now; revisit after the main split lands.
- Changing the fork's compositor `main` branch to track upstream more
  closely. That is a separate cleanup pass.

## Pre-flight inventory (verified 2026-04-29)

| Item | Value |
|---|---|
| Fork on disk | `~/git/github/somewm` (207 M, .git=45 M) |
| somewm-one tree | 20 M, mostly wallpapers; 35 commits after subtree split |
| somewm-shell tree | 1.4 M; 25 commits after subtree split |
| somewm-shell-ai tree | 48 K (deferred) |
| Working tree state | dirty: wallpaper 8.jpg → 8.png swap + uncommitted YT description |
| Backup | `~/git-backups/somewm-pre-split-20260429-084301/` (mirror + tar 55 M) |
| Subtree-split smoke test | OK — both extracted branches have clean trees + own deploy.sh |
| Secret scan | clean — only false positives (animation tokens, theme tokens, lexer tokens) |

## Decisions (locked)

| # | Question | Decision |
|---|---|---|
| 1 | History | **Preserve** via `git subtree split`. |
| 2 | New repo visibility | **Public**, with README that leads with upstream + tooling note that the canonical compositor lives at `trip-zip/somewm`. |
| 3 | Scripts (`somewm-snapshot.sh`, `install-scenefx.sh`, `start.sh`, `somewm-sandbox.sh`, `somewm-memory-*.sh`) | Stay in fork under `plans/scripts/`. Only the per-project `deploy.sh` lives in each project repo. |

## Migration playbook

Each step is independently reversible up to step 7. Step 7 is the one
destructive moment (rm of `plans/project/somewm-{one,shell}` from the fork)
and only happens after the new repos are confirmed pushed and clonable.

### Step 0 — Confirm prerequisites (no changes)

```bash
gh auth status                                      # raven2cz authenticated
gh api user --jq '.login'                           # → "raven2cz"
git -C /home/box/git/github/somewm status --short   # capture dirty state
ls /home/box/git-backups/somewm-pre-split-20260429-084301/    # backup exists
```

If `gh auth status` is not raven2cz, stop and re-auth. If working tree is
dirty, stash or commit before step 4 (subtree split runs against HEAD).

### Step 1 — Park dirty working tree

The current working tree has uncommitted wallpaper file changes and an
untracked `plans/docs/youtube-trailer-description.md`. These must not bleed
into the split.

```bash
cd /home/box/git/github/somewm
git stash push -u -m "pre-repo-split parking $(date -Iseconds)" -- \
    plans/project/somewm-one/themes/default/wallpapers/ \
    plans/docs/youtube-trailer-description.md \
    plans/project/somewm-one/themes/default/wallpapers/8.png
git status --short                                  # should now be clean
```

Stash gets restored at the end.

### Step 2 — Run the split against the live fork

We use the live fork (not the backup mirror) so the resulting
`export/somewm-{one,shell}` branches reference HEAD on `main`.

```bash
cd /home/box/git/github/somewm
git checkout main
git pull --ff-only origin main

git subtree split --prefix=plans/project/somewm-one   -b export/somewm-one
git subtree split --prefix=plans/project/somewm-shell -b export/somewm-shell

# Sanity: verify content + commit count
git log --oneline export/somewm-one   | wc -l       # expect ~35
git log --oneline export/somewm-shell | wc -l       # expect ~25
git ls-tree --name-only export/somewm-one  | head   # expect rc.lua, fishlive/, ...
git ls-tree --name-only export/somewm-shell | head  # expect components/, core/, ...
```

These two branches stay in the fork as a paper trail of where the split
happened — they do NOT get pushed to `origin/main` and they do NOT modify
the fork's published history.

### Step 3 — Create empty GitHub repos

```bash
gh repo create raven2cz/somewm-one \
    --public \
    --description "AwesomeWM-style rc.lua + themes for SomeWM (Lua framework for Wayland desktops)" \
    --homepage "https://somewm.org"

gh repo create raven2cz/somewm-shell \
    --public \
    --description "Quickshell-based desktop shell for SomeWM — panels, dashboard, launcher, control panel" \
    --homepage "https://somewm.org"
```

`gh repo create` without `--clone` creates an empty repo (no auto-README,
no auto-license — clean push target for the split branch).

### Step 4 — Push split branches as `main`

```bash
cd /home/box/git/github/somewm

git push git@github.com:raven2cz/somewm-one.git   export/somewm-one:main
git push git@github.com:raven2cz/somewm-shell.git export/somewm-shell:main

gh repo view raven2cz/somewm-one   --json url --jq '.url'
gh repo view raven2cz/somewm-shell --json url --jq '.url'
```

If either push fails, abort here. The fork is untouched, the new repos are
empty, and we can retry.

### Step 5 — Clone new repos into `~/git/github/`

```bash
cd /home/box/git/github
git clone git@github.com:raven2cz/somewm-one.git
git clone git@github.com:raven2cz/somewm-shell.git

ls -la /home/box/git/github/somewm-one/deploy.sh
ls -la /home/box/git/github/somewm-shell/deploy.sh
```

### Step 6 — Patch the new repos so they stand on their own

For both new repos:

1. **README.md** — already exists from the split, but lead paragraph must say:
   "This is the config / shell I run on top of SomeWM. The compositor itself
   lives at upstream `trip-zip/somewm` and `somewm.org`."

2. **deploy.sh** — currently uses
   `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/somewm-snapshot.sh`
   which is relative to the *old* monorepo layout. Fix to either:

   - Absolute path: `~/git/github/somewm/plans/scripts/somewm-snapshot.sh`
   - Or feature-detect and skip: `if [ -x "$SNAPSHOT_SCRIPT" ]; then ... fi`
     (already guarded, so just update the path).

   Same for any other relative script reference.

3. **CLAUDE.md** (or `AGENTS.md`) — new file in each repo, short, pointing at
   the parent fork's CLAUDE.md for compositor/IPC conventions.

4. **.gitignore** — copy/create from current fork-side ignores (`.active_theme`,
   `.default_portrait`, `rc.lua.bak`, `themes/*/user-wallpapers/`).

Commit + push each repo independently:
```bash
git -C /home/box/git/github/somewm-one   add -A
git -C /home/box/git/github/somewm-one   commit -m "chore: standalone repo bootstrap (deploy paths, README, CLAUDE.md)"
git -C /home/box/git/github/somewm-one   push origin main

git -C /home/box/git/github/somewm-shell add -A
git -C /home/box/git/github/somewm-shell commit -m "chore: standalone repo bootstrap (deploy paths, README, CLAUDE.md)"
git -C /home/box/git/github/somewm-shell push origin main
```

### Step 7 — Smoke-test the new repos before fork cleanup

This is the gate. If anything below fails, do NOT touch the fork.

```bash
# Deploy from the new repo, exactly as the user would
~/git/github/somewm-one/deploy.sh --dry-run
~/git/github/somewm-shell/deploy.sh --dry-run

# Run actual deploy if dry-run is clean
~/git/github/somewm-one/deploy.sh
~/git/github/somewm-shell/deploy.sh

# Reload compositor and verify nothing broke
somewm-client reload
somewm-client eval 'return awesome.version'         # confirm IPC alive
```

Visual smoke check (user-driven): open Dolphin, switch a tag, open
control panel, trigger notification. Anything weird → rollback per the
rollback section below.

### Step 8 — Remove the projects from the fork

Only after step 7 passes.

```bash
cd /home/box/git/github/somewm
git checkout main

git rm -r plans/project/somewm-one
git rm -r plans/project/somewm-shell
# somewm-shell-ai stays for now — see "Out of scope".

git commit -m "$(cat <<'EOF'
chore: split somewm-one and somewm-shell into standalone repos

Both projects now live at:
  - https://github.com/raven2cz/somewm-one
  - https://github.com/raven2cz/somewm-shell

The fork (this repo) goes back to being a working tree for upstream PRs
to trip-zip/somewm. Users should install upstream from somewm.org.

History was preserved via git subtree split before deletion; the export
branches (export/somewm-one, export/somewm-shell) remain locally as a
paper trail.
EOF
)"
git push origin main
```

### Step 9 — Update fork's `CLAUDE.md` and `AGENTS.md`

The "User Configuration", "somewm-one", "Plans Directory" sections of
`/home/box/git/github/somewm/CLAUDE.md` reference the old `plans/project/`
paths. Rewrite each affected section to:

- Point at `~/git/github/somewm-one` and `~/git/github/somewm-shell` as
  sibling working dirs.
- Note that compositor scripts (`install-scenefx.sh`, `start.sh`,
  `somewm-sandbox.sh`, memory diagnostics) stay in this repo.
- Note that `deploy.sh` lives in each project repo independently.

Same for `AGENTS.md`.

### Step 10 — Restore parked work

```bash
cd /home/box/git/github/somewm
git stash list                                      # find the parking stash
git stash pop                                       # or: git stash apply stash@{N}
```

Wallpaper and YT description changes come back. Decide separately whether
they belong in the fork (probably the YT desc moves to somewm-one) or
need to be re-deployed.

### Step 11 — Update YouTube + Reddit copy

Out of scope for this plan but tracked here so it isn't forgotten:

- Edit `plans/docs/youtube-trailer-description.md` (or move it to
  `somewm-one/docs/`) so primary links point at upstream + new repos.
- Reddit body for any future post: upstream first, no `🔱 my fork` bullet.

## Rollback

The plan has three rollback gates:

| Failure point | Rollback |
|---|---|
| Step 2 (subtree split errored) | `git branch -D export/somewm-one export/somewm-shell` and re-investigate. Fork untouched. |
| Step 4 (push to new repo failed) | Delete the empty GH repo: `gh repo delete raven2cz/somewm-one --yes`. Fork untouched. |
| Step 7 (smoke test failed) | Delete new GH repos, remove cloned working dirs, fork still intact. Investigate before retrying. |
| After step 8 (regret post-cleanup) | Restore from `~/git-backups/somewm-pre-split-20260429-084301/somewm.git` mirror clone, force-push the fork's main back to pre-split state. Last resort — costs commits made between split and rollback. |

The mirror backup makes the worst-case recoverable but loud (force-push).
Prefer to catch issues at step 7.

## Risks and mitigations

1. **Public exposure of fork-promotion artifacts.** The fork's existing
   commits already mention `plans/project/somewm-{one,shell}`. After the
   split, those paths still exist in fork history (any commit before the
   split). Anyone reading the fork's old log will still see that the projects
   used to live there. This is unavoidable without a full force-push history
   rewrite, which we are not doing. Acceptable risk: nobody hunts through
   git history for marketing.
2. **Script bit-rot.** `deploy.sh` in each new repo references compositor
   scripts via absolute path. If the user ever moves the fork checkout, both
   project repos break. Mitigation: relative-path detection with sane
   fallback when scripts are not present (just skip the snapshot, deploy
   anyway).
3. **Memory carry-over.** Several memory entries
   (`feedback_qs_deploy.md`, `feedback_deploy_automaticky.md`,
   `feedback_never_deploy_live.md`) reference the old paths. After step 9,
   sweep these to point at the new working dirs.
4. **Cross-repo IPC drift.** When a new compositor signal is added that
   `somewm-shell` consumes, both repos need a coordinated commit. No tooling
   prevents this. Mitigation: keep IPC contracts documented in
   `IPC.md` (already exists in somewm-shell). For now this is just
   discipline.

## Open questions for the user

1. **Stash vs commit before split?** The dirty wallpaper changes (`.jpg → .png`
   for wallpaper 8) — do you want those committed first as a normal commit,
   or stashed away and re-applied after the split? Committed-first makes the
   split history slightly cleaner; stash is safer if you want to rethink
   those changes later.
2. **`plans/docs/youtube-trailer-description.md`** — keep in fork (it's a
   project artifact about somewm overall), or move into somewm-one/docs/
   when the split lands? My read: it's about the project, not the config,
   so it could stay in fork. But if the fork goes "quiet", the somewm-one
   repo is more visible.
3. **`somewm-shell-ai`** — defer (current plan), or split as a third repo
   right now? It's tiny (48 K) but it's also the kind of thing that gets
   public attention if you ever ship it. Defer is safer.
4. **Topic tags on new GH repos.** `gh repo create --topic ...` lets us tag
   `wayland`, `awesomewm`, `quickshell`, `lua`, `desktop-shell`. Worth doing
   for discoverability. Want me to include those in step 3?
