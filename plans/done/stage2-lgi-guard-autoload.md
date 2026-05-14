# Stage 2: Lgi closure guard auto-load (cherry-pick from upstream)

## Status: TODO (separate branch, low-medium risk)

Navazuje na `plans/done/cherry-pick-upstream-hotreload.md` — Stage 1 (a/b/c) mergnuto
2026-04-16 do main, Stage 2 přesunuto do samostatné branche podle Codex doporučení.

## Cíl

Nahradit manuální `LD_PRELOAD=liblgi_closure_guard.so` setup v
`plans/scripts/start.sh` upstream auto-load mechanismem:

1. Compositor při startu detekuje, že nemá guard naloaděn.
2. Re-execne sám sebe s `LD_PRELOAD=$SOMEWM_LIBDIR/liblgi_closure_guard.so`.
3. Fallback search přes `lib`, `lib64`, system paths pro non-standard distros.
4. Graceful warning pokud guard chybí, místo tichého selhání.
5. `unsetenv("LD_PRELOAD")` ve child procesech (už máme — `05b7f21`).

Benefit: out-of-the-box funkční hot-reload pro jiné package manageři (Gentoo
lib64, AUR, custom installs) bez nutnosti úpravy `start.sh`.

## Cherry-pick sekvence

Všechny 3 commity závisí na sobě — aplikovat v pořadí:

| Upstream hash | Datum | Soubory | Co |
|---------------|-------|---------|-----|
| `67d7899` | 2026-03-23 | `meson.build`, `somewm.c::main()` | přidá `-DSOMEWM_LIBDIR`, re-exec logic |
| `ace15ed` | 2026-03-27 | `somewm.c` | fallback search paths (lib/lib64/system) |
| `b6b2e78` | 2026-04-01 | `common/luaobject.c`, `globalconf.h`, `luaa.c`, `objects/spawn.h`, `somewm.c`, `spawn.c` | log polish + dev build dir support |

Dry-run ověření: sequenčně všechny 3 mergují čistě proti `fix/upstream-hotreload-cherrypick`
baseline (ověřeno v cherry-pick plánu 2026-04-15).

## Workflow

```bash
# Branch z aktuálního main (po Stage 1 merge)
git checkout main && git pull origin main
git checkout -b fix/lgi-guard-autoload

# Cherry-pick v pořadí
git cherry-pick 67d7899
git cherry-pick ace15ed
git cherry-pick b6b2e78

# Build
~/git/github/somewm/plans/scripts/install-scenefx.sh

# Ověřit, že guard se naloadě bez manuálního setup
# (nejdřív vykomentovat LD_PRELOAD v start.sh)

# Smoke test
# 1. start.sh restart
# 2. journalctl | grep "lgi_guard" — potvrzení auto-load
# 3. 3x reload → no SEGV
# 4. Otevřít Firefox → `cat /proc/$(pgrep firefox)/environ | tr '\0' '\n' | grep LD_PRELOAD` — musí být prázdné
```

## Po-úspěch: upravit start.sh

```bash
# Odstranit manuální LD_PRELOAD řádek z plans/scripts/start.sh
# Commit:
git commit -am "fix(start): remove manual LD_PRELOAD — upstream auto-load handles it"
```

## Riziko

**Medium** (vs Low pro Stage 1) — dotýká se `main()` re-exec cesty a env
manipulace. Test plan nad rámec smoke testu:

- Ověřit argv preservation přes re-exec (žádný arg se neztratí/zdvojí)
- Ověřit, že env proměnné somewm potřebuje (WLR_*, XDG_*, DBUS_*) přežijí re-exec
- Ověřit dev build (`build-fx/somewm`) najde guard přes `--search-paths` override
- Potvrdit, že child procesy (alacritty, Firefox, Steam) opravdu nedědí LD_PRELOAD

## Rollback

```bash
# Selhání kteréhokoli ze 3 commits
git reset --hard main
# start.sh manuální LD_PRELOAD zůstává funkční — bez regrese
```

## Otevřené otázky

1. Je naše `start.sh` dnes ještě jediné startup místo, nebo se používá i něco
   jiného (DM launch, systemd --user unit)? Pokud ano, všude upravit.
2. Jaký je build-dir layout po meson — najde `b6b2e78` náš `build-fx/` i
   `build/`?

## Reference

- Původní plán: `plans/done/cherry-pick-upstream-hotreload.md` (Stage 2 section)
- Codex review 2026-04-15: doporučeno separate branch kvůli rozsahu env manipulace
