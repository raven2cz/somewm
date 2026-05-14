# Investigate: Shadow nerenderuje na startu, když je `color` v user tabulce nil

## Status: TODO (otevřený plán — diagnostický, ne krátký fix)

## Pozorovaný problém

Uživatel v `awful.wibar{ shadow = {...} }` předává `shadow` tabulku bez `color` klíče
(buď ho explicitně neuvede, nebo `color = beautiful.shadow_drawin_color` vrátí `nil`
protože theme tenhle klíč nedefinuje).

**Výsledek:**
- Na **startu** z TTY: shadow se **nevykreslí**, přestože všechna data
  (enabled=true, radius, opacity, offset_x/y, color) jsou v `drawin.shadow`
  strukturách OK (ověřeno přes `somewm-client eval`).
- Po prvním **reloadu**: shadow se náhle objeví, dál funguje korektně.

## Reprodukce

Dvě sandbox konfigurace se stejným rc.lua a stejným binárem, liší se **jen**
přítomností `color` klíče v `awful.wibar{ shadow = {...} }`:

| Test | `color` field v Lua user tabulce | Shadow na startu |
|------|----------------------------------|------------------|
| C    | `color = "#000000"` (hardcoded)  | **ANO** |
| D    | `color = nil` (beautiful nemá klíč) | **NE** |
| E    | `color = "#000000"` (beautiful má klíč) | **ANO** |

Sandbox protokol v `plans/scripts` + `CLAUDE.md` (WLR_BACKENDS=wayland +
XDG_CONFIG_HOME override).

Bisection + empirické ověření 2026-04-16.

## Nejasnost

Data v `drawin.shadow` struktuře jsou pro Test C a Test D **identická**
(enabled=true, r=30, op=0.5, ox=0, oy=6, col=#000000). Render výstup se
přesto liší. **Příčina na C úrovni není identifikovaná** — pouze vyloučeny:

- Není to pořadí `luaA_class_new` setterů (property `shadow` je jeden setter,
  ne per-field).
- Není to `shadow_load_beautiful_defaults` timing (obě varianty ho vidí
  před wibar createm).
- Není to `pairs()` iterace (`shadow_config_from_lua` používá explicitní
  `lua_getfield` per klíč).
- Není to hodnota `config->color[]` — v obou případech je `{0,0,0,1}`.

Empirický workaround aplikovaný v `somewm-one`:
- `plans/project/somewm-one/themes/default/theme.lua:66` —
  `theme.shadow_drawin_color = "#000000"` (bez toho regrese).
- Obchází bug, ale nezachraňuje generické usery, kteří `color` klíč vypustí.

## Hypotéza pro další kolo

Side-effect `luaA_drawin_set_shadow` chování se liší podle toho, zda `color`
field byl v Lua tabulce přítomen (string → setter cesta v
`shadow_config_from_lua` s `color_init_from_string`) vs. absent (nil → preserved
default z `globalconf.shadow.drawin`). I když výsledný `shadow_config_t`
je binárně shodný, **scene damage nebo texture regen se možná triggeruje
jen v první variantě**.

## Co udělat (instrumentace, ne fix)

Navazuje na `memory/feedback_diagnostika_pred_hypotezou.md` — nejdřív data,
pak hypotéza.

1. Přidat `WLR_ERROR` logy do:
   - `shadow.c:shadow_config_from_lua` — logovat vstup (zda color field je
     nil, string, nebo table; hodnoty všech polí před i po parsing).
   - `shadow.c:shadow_update_config` — logovat config hash, scene_tree ptr,
     width/height před shadow_destroy a po shadow_create.
   - `shadow.c:shadow_create` — logovat které shadow varianta se vytváří
     (SceneFX wlr_scene_shadow vs 9-slice CPU fallback), zda
     `wlr_scene_shadow_set_size` projde.
   - `objects/drawin.c:luaA_drawin_set_shadow` — logovat drawin ptr,
     scene_tree existence při volání, visibility.
   - Pokud potřeba: `shadow_set_visible`, damage marking cesty v
     scenefx/scene.

2. Spustit **Test C** (color="#000000") a **Test D** (color=nil) ve stejném
   sandboxu postupně, ukládat logy do dvou souborů.

3. **Porovnat řádek po řádku** (`diff -u`). První rozdíl v logu = root cause
   poloha.

4. Teprve pak navrhnout čistý fix — buď:
   - C-side safety net: vždy volat `color_init_from_string` default, nebo
   - Vždy re-apply `wlr_scene_shadow_set_size`/damage po `set_shadow`, nebo
   - Fix v render cestě (scenefx `wlr_scene_shadow` damage na startu).

5. Fix by měl být **generický** (část somewm frameworku), ne dependency na
   theme klíč. Viz `memory/feedback_somewm_generic_only.md`.

## Upstream relevance

Potenciálně PR na `trip-zip/somewm` — fix je generic, netýká se jen
raven2cz forku. Ale nejdřív čistá C-side analýza.

## Artefakty z bisection session 2026-04-16

- Memory: `memory/project_scenefx_shadow_startup.md` (bisection matrix)
- Logs (pokud ještě existují v `/tmp/`):
  `somewm-testC-current-hardcoded.log`, `somewm-testD-current-original.log`,
  `somewm-testE.log`

## Kdo by to měl dělat

Sonnet/Opus v oddělené session s ~1-2h focus. Claude Opus 4.6 pro C-side
analýzu, nebo gpt-5.4 codex pro paralelní pohled.
