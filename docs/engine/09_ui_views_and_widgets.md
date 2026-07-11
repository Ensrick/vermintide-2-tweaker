# Engine reference 09 - UI views, widgets and rendering

Engine reference for VT2's menu/HUD stack: IngameUI + view lifecycle, UIWidget /
UIRenderer / materials and atlases, `create_screen_gui` constraints, hero and
inventory views, input services - plus how gut / cim / cosmetics hook into it.

Citation convention: vanilla paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to
the monorepo root. Decompiled line numbers can drift a few lines from shipped
runtime lines (e.g. `ui_renderer.lua` Gui.video shipped `:1345` vs decompiled
`:1296` - BUG_CLASSES.md §23); prefer citing the decompiled number and note the
drift when matching a crash log.

Adjacent docs: `docs/BUG_CLASSES.md` §22/§23, `docs/VMF_RECIPES.md`,
`memory/reference_vt2_*` (options widgets, widget timing, menu button overlay,
create_screen_gui crash, keep-only materials, OptionsView cb_ takeover).

---

## 1. Architecture map

| File (vanilla) | Class / table | Single responsibility |
|---|---|---|
| `scripts/ui/views/ingame_ui.lua` | `IngameUI` | Root menu controller per game state: owns the two screen renderers, the `views` table, the transition machine, popups, and delegates HUD to IngameHud (`:55-139` init) |
| `scripts/ui/views/ingame_ui_settings.lua` | (module) | Data for IngameUI: `transitions` closures (`:37-560`), `ui_renderer_function` material lists (`:561-652`), `views_function` (`:731-767`), `hotkey_mapping` (`:768-881`) |
| `scripts/managers/ui/ui_manager.lua` | `UIManager` (`Managers.ui`) | Creates/destroys/updates the IngameUI (`:17-42`, `:92-129`); public transition entry `Managers.ui:handle_transition(name, params)` with `params.use_fade` (`:226-238`) |
| `scripts/ui/ui_renderer.lua` | `UIRenderer` | Stateless draw API over an engine `Gui`: `create` funnels every material into `World.create_screen_gui` (`:246-251`), `begin_pass`/`draw_widget`/`end_pass` (`:332-365`, `:387+`), bitmap/text/video draw helpers, atlas resolution (`:60-119`) |
| `scripts/ui/ui_widget.lua` | `UIWidget` | Widget instantiation from a definition: clones content/style, builds a FIXED-size `pass_data` array (`:13-46`); `UIWidget.destroy` tears down retained passes (`:48-64`) |
| `scripts/ui/ui_passes.lua` | `UIPasses` | Per-pass-type init/update/draw. `texture` draw ~`:120-143`, `texture_uv` `:145+`, `hotspot` `:4224` (writes `is_hover`/`is_held`/`on_hover_enter`/`on_release` into pass content) |
| `scripts/ui/ui_scenegraph.lua` | `UISceneGraph` | Node tree -> world positions: `init_scenegraph(def)` (`:154`), `update_scenegraph` (`:209`), scaled size lookups |
| `scripts/helpers/ui_atlas_helper.lua` | `UIAtlasHelper` | Texture-name -> atlas-settings lookup: `get_/has_atlas_settings_by_texture_name` (`:593`, `:605`), backed by every `scripts/ui/atlas_settings/gui_*_atlas.lua` require (`:3-30+`) |
| `scripts/ui/ui_widgets.lua` (+ `_store`/`_weaves`/`_honduras`) | `UIWidgets` | Widget-definition factories (e.g. `create_simple_texture` `ui_widgets.lua:5268`; `create_default_button` lives in `ui_widgets_honduras.lua`) |
| `scripts/ui/views/ingame_hud.lua` | `IngameHud` | In-mission HUD component host: builds the component list per game mode (`:44-50`), instantiates by `class_name` with `validation_function` gates (`:180-206`), visibility groups (`:67-155`), `component()` / `get_hud_component()` accessors (`:256`, `:336`) |
| `scripts/ui/views/hero_view/hero_view.lua` | `HeroView` | The keep menu shell: own input service (`:56-59`), a `GameStateMachine` of HeroViewState* (`:82-97`), keep-only HDR worlds/renderers (`:136-180`) |
| `scripts/ui/views/hero_view/states/hero_view_state_overview.lua` | `HeroViewStateOverview` | Window layout host: `_active_windows` array (`:250-263`), window create/swap/close (`:282-338`), per-frame `window:update(dt, t)` (`:477-480`), `window_input_service()` (`:265-267`) |
| `scripts/ui/views/options_view.lua` | `OptionsView` | The ESC settings menu: builds widget lists from definitions (`build_settings_list :1029`), per-type factories (`build_drop_down_widget :1270`, `build_checkbox_widget :1483`), staged apply (`_set_setting :1825`) |
| `scripts/ui/views/options_view_settings.lua` | (module) | Settings definitions; `generate_settings` synthesizes three REAL named `cb_*` methods on OptionsView per `setting_name` entry (`:1298-1333`) |
| `scripts/managers/input/input_manager.lua` | `InputManager` | Named input services: `create_input_service` (`:593-617`, overwrites on re-create `:614` - idempotent), `map_device_to_service` (`:639`), `get_service` (`:788-794`, returns nil for unknown name), device blocking (`:175`, `:246`) |
| `scripts/helpers/ui_utils.lua` | `FAKE_INPUT_SERVICE` | Inert input service stub (`:6`) used while views load/transition (`hero_view.lua:107-109`) |
| `scripts/helpers/dlc_utils.lua` | `DLCUtils` | Iterates `DLCSettings[*].<key>` lists (`map_list :21-31`, `merge :64-72`) - the injection surface `views_function` reads |

Key ours:

| File (ours) | Responsibility |
|---|---|
| `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_gui_material_guard.lua` | The repo's Gui-material crash-class mitigation: one consolidated `UIRenderer.create` hook that DROPS non-resident materials and INJECTS keep-only atlases when resident (`:298-305` hook, `:135-293` `_prepare`) |
| `gui_tweaker_dev/.../gui_tweaker_dev.lua:1083-1318` | Custom-view registration: `_attach_view` into `IngameUI.views`, transition closure injected into `package.loaded["scripts/ui/views/ingame_ui_settings"].transitions`, `Managers.ui:handle_transition` opener |
| `gui_tweaker_dev/.../_mod_tweaker_view.lua` | The canonical full custom view (borrowed renderer, own scenegraph, own input service, full IngameUI view interface) |
| `gui_tweaker_dev/.../_gut_ckc_bridge.lua` | Issue #313 worked example: OptionsView `cb_*` takeover + widget augmentation via UIWidget re-init (`:166-220`, `:317-321`) |
| `crafting_in_modded_dev/.../crafting_in_modded_dev.lua:2108-2556` + `:4078` | Weave-forge (Athanor) mid-mission enablement: viewport/env/HDR-renderer hooks + parent-state `update` driver |
| `crafting_in_modded_dev/.../_accessory_craft_panel.lua` | Own-scenegraph button overlay nested in a vanilla window (drawn off `HeroWindowWeaveProperties._draw`) |
| `cosmetics_tweaker/.../_glow_picker.lua` (+ hooks `cosmetics_tweaker.lua:9602-9640`) | The proven own-scenegraph popup overlay pattern |

---

## 2. Lifecycle and data flow

### 2.1 IngameUI creation -> destruction (once per StateIngame)

1. `UIManager.create_ingame_ui` (`ui_manager.lua:17`) news up `IngameUI` with the
   `ingame_ui_context`.
2. `IngameUI.init` (`ingame_ui.lua:55-139`): creates `ui_renderer` (level_world)
   and `ui_top_renderer` (top_ingame_view world) via
   `view_settings.ui_renderer_function` (`:76-77`, `:141-143`) - the material
   list is decided HERE by `is_in_inn` / `is_tutorial` / mechanism
   (`ingame_ui_settings.lua:561-652`). Creates the `"ingame_menu"` input service
   (`:89-92`), news `IngameHud` (`:103`), then `setup_views` (`:107` - NOTE: the
   context is passed as an ARG; `self.ingame_ui_context` is only stored at
   `:138`, after setup_views returns).
3. `setup_views` (`:145-148`) -> `views_function`
   (`ingame_ui_settings.lua:731-767`): news every vanilla view class with the
   context, then iterates `DLCSettings[*].ui_views` entries
   (`:745-764`, `fassert` on duplicate names `:754`, mechanism / only_in_inn /
   only_in_game filters `:756-758`) and news `_G[view.class_name]`.
4. Per frame, `UIManager.update` (`ui_manager.lua:92-129`) calls
   `IngameUI.update` (`ingame_ui.lua:524-688`): fade transitions (`:527`),
   popups (`:551-557`), then **if a view is open, only that view's
   `update(dt, t)` runs** (`:596-604`); toggle-menu ESC handling (`:623-650`);
   menu hotkeys (`:652-662`); `IngameHud.update` only when a network game exists
   (`:677-679`); chat/menu input-block bookkeeping (`:681`). `post_update`
   (`:700-714`) runs `_post_handle_transition` FIRST, then the view's
   `post_update`.
5. `IngameUI.destroy` (`:221-306`): calls `on_exit` on the OPEN view
   **unguarded** (`:234-240` - no `.on_exit` nil-check, unlike
   `handle_transition`'s guarded call at `:955`), then `view:destroy()` for
   every view that has one (`:242-246`), then `UIRenderer.destroy` both
   renderers (`:299-300`). A custom view that can be open across a level
   transition MUST implement `on_exit`.

### 2.2 View transitions

- `IngameUI.handle_transition(name, params)` (`ingame_ui.lua:925-980`):
  `fassert`s the transition exists (`:926`), refuses repeats of the same
  transition (`:934-938`), snapshots `old_view = self.current_view` (`:946`),
  invokes the transition closure (`:948`) - closures just mutate
  `self.current_view` / `self.menu_active` (vanilla pattern:
  `ingame_ui_settings.lua:430-559`, e.g. `options_menu` `:537-539`, `exit_menu`
  `:506-519`). Then, **only if `old_view ~= new_view or params.force_open`**
  (`:953`): old view `on_exit` (guarded, `:954-960`), new view `on_enter`
  (`:970-973`). `force_open` is load-bearing for re-entering hero_view with a
  different sub-state (every keep ESC-menu button uses it - see
  `gui_tweaker_dev.lua:1216-1227` commentary citing
  `ingame_view_menu_layout_console.lua:742-745`).
- `post_update_on_enter` / `post_update_on_exit` fire one frame later from
  `_post_handle_transition` (`:894-923`) - `post_update_on_enter` is the ONLY
  consumer of `params.menu_state_name` in HeroView (`hero_view.lua:504-508`
  [per gut's verified comment at `gui_tweaker_dev.lua:1221-1223`]).
- `transition_with_fade` (`:982-1002`) stages the transition and runs it when
  `Managers.transition:fade_in_completed()` (`:1004-1025`).
- Public entry from mod code: `Managers.ui:handle_transition(name, params)`
  (`ui_manager.lua:226-238`); `params` is REQUIRED (fassert `:227`),
  `params.use_fade = true` routes through `transition_with_fade`.
- View replacement at runtime: `IngameUI.setup_specific_view(key, class_name)`
  (`:150-161`) destroys and re-news one view - vanilla uses it on DLC status
  change (`:512-518`).

### 2.3 HeroView -> states -> windows

- `HeroView` is ONE IngameUI view; its screens are a `GameStateMachine` of
  `HeroViewState*` (`hero_view.lua:82-97`); the state to open comes from
  `params.menu_state_name` via `settings_by_screen`.
- `HeroViewStateOverview` hosts up to `max_active_windows` window objects
  (`hero_view_state_overview.lua:154`, `:250-263`). `_change_window`
  (`:294-338`) resolves the class by `rawget(_G, class_name)`, news it, computes
  the window x-offset, and calls `window:on_enter(params, offset)`. Windows die
  via `on_exit` (`:282-292`).
- Per frame the state calls `window:update(dt, t)` on every active window
  (`:477-480`). **A window's `update` can run BEFORE its widget tables exist**
  - the first frames precede/race `create_ui_elements`, so
  `window._widgets` / `_widgets_by_name` read nil from a child-window `update`
  hook (memory `reference_vt2_widget_timing_pattern`; burned cim v0.7.57-dev).
  Drive per-frame widget mutation from the PARENT state's `update` instead
  (cim does: `crafting_in_modded_dev.lua:4078` hooks
  `HeroViewStateWeaveForge.update`).
- Keep-only extras: `HeroView._setup_hdr_gui` builds two extra HDR worlds +
  renderers ONLY `if self.is_in_inn` (`hero_view.lua:136-165`), each with
  shading env `environment/ui_hdr` (`:167-180`). Mid-mission forced opens must
  compensate (cim hooks `HeroView._setup_hdr_gui` `crafting_in_modded_dev.lua:2454`,
  `hdr_renderer`/`hdr_top_renderer` `:2549-2556`).
- Window input: `state:window_input_service()` returns `FAKE_INPUT_SERVICE`
  while input-blocked (`hero_view_state_overview.lua:265-267`); windows never
  own services.

### 2.4 Widgets and the draw pass

- A widget DEFINITION is `{ scenegraph_id, element = { passes }, content,
  style, offset }`. `UIWidget.init` (`ui_widget.lua:13-46`) CLONES content and
  style (`:14-16`), runs each pass's `init`, and sizes `pass_data` as a fixed
  `Script.new_array(num_passes)` (`:19-26`). Consequence: **you cannot append
  passes to a live widget** - append to `element.passes` + content/style, then
  re-run `UIWidget.init` and use the NEW widget (issue #313 pattern, §3.4).
- Draw: `UIRenderer.begin_pass(renderer, scenegraph, input_service, dt,
  parent_scenegraph_id, render_settings)` (`ui_renderer.lua:332-351`) updates
  the scenegraph and stashes per-pass state on the renderer; then
  `UIRenderer.draw_widget` per widget (`:387+`): runs `UIAnimation`s
  (`:388-398`), computes position = node world_position + widget offset
  (`:406-410`), and for each pass evaluates `content_check_function` /
  `content_change_function` visibility (`:478-494`) and calls
  `UIPasses[pass_type].update` (`:496-501`); retained-mode passes only redraw
  when dirty (`:503-519`). `end_pass` pops the scenegraph queue (`:353-365`).
  Nested passes are legal if you pass `parent_scenegraph_id` (`:339`).
- Hotspot feedback fields (`ui_passes.lua:4224`) are (re)written during the
  draw; read `on_release` / `is_hover` AFTER the pass and set consumed edges
  false (memory `reference_vt2_ui_button_sound_use_window_play_sound`).

### 2.5 Materials and atlases - two-stage resolution

1. At GUI CREATE time, `UIRenderer.create(world, "material", path, ...)`
   (`ui_renderer.lua:246-251`) passes every listed material to
   `World.create_screen_gui`. The per-context material list is baked in
   `ingame_ui_settings.lua`: base list `:563-580`; keep-only extras appended
   only `if is_in_inn` (`:582-614` - achievement atlas, inn singles, lock
   test, pose cosmetics, tutorial videos, AreaSettings area videos `:594-601`,
   DLC `ui_materials_in_inn` `:603-613`); DLC `ui_materials` `:616-626`;
   career videos `:633-640`.
2. At DRAW time, `UIRenderer.script_draw_bitmap` (`:60-119`) resolves the
   texture NAME through `UIAtlasHelper.has_atlas_settings_by_texture_name`
   (`:74-76`): a hit maps to the atlas's master material + UVs (`:84-113`); a
   MISS passes the literal name to `Gui.bitmap` as a material (`:117`) - which
   C-fatals if that material is not in the Gui's baked list.

Fast classification of any texture name (memory
`reference_vt2_options_widgets_raw_materials`): grep
`Vermintide-2-Source-Code/scripts/ui/atlas_settings/` for it - a hit = atlas
backed (drawable on any renderer whose master atlas is loaded); no hit = raw
material that must be in the Gui's create-time list.

### 2.6 IngameHud components

`IngameHud._setup_components` picks the component list file from
`game_mode_settings.hud_component_list_path` (`ingame_hud.lua:44-50`), requires
each component's file (`:143-145`), and instantiates classes whose
`validation_function(ingame_ui_context, is_in_inn)` passes (`:180-206`).
Components are looked up by CLASS NAME via `ingame_hud:component("IngamePlayerListUI")`
(`:256`) or by registered hud name via `get_hud_component` (`:336`). HUD classes
under `scripts/ui/hud_ui/` are lazily loaded (mission-time), so string-form VMF
hooks on them error `trying to hook object that doesn't exist` at the keep -
prefer data fixes or lazy registration (memory
`reference_vmf_hud_ui_class_hook_fails_at_keep`).

### 2.7 Input services

- Each view owns a NAMED service: `"ingame_menu"` (`ingame_ui.lua:89-92`),
  `"hero_view"` (`hero_view.lua:56-59`), `"options_menu"`
  (`options_view.lua:274`). Creation is idempotent -
  `create_input_service` simply overwrites the slot
  (`input_manager.lua:612-616`); `get_service` returns nil for an unknown name
  (`:788-794`).
- IngameUI decides which service is "live" each frame in
  `_menu_blocking_information` (`ingame_ui.lua:754-807`): an open view's
  `input_service()` wins (`:768-772`); a view must therefore implement
  `input_service()`.
- Blocking: transitions block/unblock devices around popups and menu entry -
  `block_device_except_service` (`input_manager.lua:175`;
  e.g. `cancel_popup` transition `ingame_ui_settings.lua:520-526`) and
  `device_unblock_all_services` (`:246`; `exit_menu` `:506-519`). Forgetting the
  unblock on a custom exit path soft-locks the game (BUG_CLASSES.md §20).

---

## 3. Hookable seams (safe patterns)

| Seam | Pattern | Trap |
|---|---|---|
| `UIRenderer.create` (`ui_renderer.lua:246`) | `mod:hook("UIRenderer", "create", ...)` - mutate the `("material", path)` token list; proven chainable (VMF custom_textures hooks it) | Rebuild the vararg with explicit count `unpack(t, 1, n)`; NEVER add a non-resident material (create C-fatal) - gate on `Application.can_get("material", path)` with a self-test (canonical: `_gut_gui_material_guard.lua:298-305`, `:113-128`) |
| `IngameUI.setup_views` (`ingame_ui.lua:145`) | `mod:hook_safe` post-call, read the context from the ARG (2nd param), attach `self.views[name] = MyView:new(ctx)` | `self.ingame_ui_context` is nil at this timing (`ingame_ui.lua:107` vs `:138`); post-Versus the hook can also see `self.views` not yet a table - keep a lazy attach fallback (`gui_tweaker_dev.lua:1083-1120`, `:1240-1243`) |
| Transitions table | Mutate `package.loaded["scripts/ui/views/ingame_ui_settings"].transitions[name] = closure` - the SAME table `ingame_ui.lua:48-50` captured | A closure sets `self.current_view` only; IngameUI runs on_exit/on_enter around it. Must run after boot (VMF mods do). Canonical: `gui_tweaker_dev.lua:1174-1266` |
| `DLCSettings[*].ui_views` | Append an entry `{ name=, class_name=, mechanism_filter=, only_in_inn= }`; `views_function` instantiates it on EVERY IngameUI init (`ingame_ui_settings.lua:745-764`) | The `ui_views` transition/hotkey merges (`:885-895`) ran at boot require time, BEFORE mods load - a mod still needs the package.loaded transition mutation; view `file` dofiles also already ran (`ingame_ui.lua:33-39`) |
| Open a view | `Managers.ui:handle_transition(name, { use_fade = true })` (`ui_manager.lua:226-238`) | params table REQUIRED (fassert). Repeat-transition guard: same transition twice in a row is dropped (`ingame_ui.lua:934-938`) |
| Re-enter hero_view on a sub-state | `ingame_ui:transition_with_fade("hero_view", { menu_state_name = X, force_open = true })` | Without `force_open`, `old_view == new_view` skips on_enter AND post_update_on_enter - the only reader of menu_state_name - so the fade plays and nothing opens (`ingame_ui.lua:953`; `gui_tweaker_dev.lua:1216-1231`) |
| Custom view interface | Implement AT MINIMUM: `update(dt,t)`, `input_service()`, `on_enter(params)`, `on_exit()`, `destroy()`; optional: `exit(return_to_game)`, `transitioning()`, `post_update*` | `IngameUI.destroy` calls the OPEN view's `on_exit` UNGUARDED (`ingame_ui.lua:234-240`); `_menu_blocking_information` calls `input_service()` unguarded (`:770`). Full reference impl: `_mod_tweaker_view.lua:1776-1957` |
| Hero window draw/update | `mod:hook_safe("HeroWindowX", "_draw"/"draw", ...)` to piggy-back an own-scenegraph overlay; get renderer from `self._ui_top_renderer or self._ui_renderer or self.ui_top_renderer or self.ui_renderer` (naming differs per window: customization uses underscore `hero_window_item_customization.lua:1006`, cosmetics loadout does not `:167`) | Never inject `UIWidgets.create_default_button` into a host window's draw arrays (screen-covering rect / corner placement / double-fire - memory `reference_vt2_menu_button_overlay_pattern`); many windows have no `_widgets`, they draw `_top_widgets`/`_bottom_widgets`/`_*_hdr_widgets` |
| Per-frame widget mutation in a window | Hook the PARENT state's `update` (e.g. `HeroViewStateWeaveForge.update`), find the window in `state._active_windows` | A child window's own `update` fires before `_widgets`/`_widgets_by_name` exist (memory `reference_vt2_widget_timing_pattern`) |
| OptionsView single-entry takeover | Hook the SYNTHESIZED named methods `cb_<setting_name>`, `cb_<setting_name>_setup`, `cb_<setting_name>_saved_value` - real methods created per entry by `generate_settings` (`options_view_settings.lua:1298-1333`) | Changes STAGE via `_set_setting` (`options_view.lua:1825`) and only commit on Apply. Worked example: `_gut_ckc_bridge.lua` (#313) |
| OptionsView widget augmentation | Wrap `build_drop_down_widget`/`build_checkbox_widget` (`options_view.lua:1270`, `:1483`), append passes+content+style, then RE-INIT: `return UIWidget.init({ element = { passes = passes }, content = content, style = style, offset = widget.offset })` (`_gut_ckc_bridge.lua:215-219`) | `pass_data` is a fixed array (`ui_widget.lua:19-26`) - in-place pass appends index past it. `widget.content.definition` is stamped AFTER the build hook returns (`options_view.lua:1108`), so it lands on your re-inited widget automatically |
| Preview worlds | `MenuWorldPreviewer.equip_item`/`_spawn_item` for keep inventory; `LootItemUnitPreviewer.spawn_units` (full `mod:hook`, NOT hook_safe) for the skin browser | HOOK THE DERIVED CLASS: `class.lua:51-57` copies parent methods at definition time, so `HeroPreviewer` hooks never fire on `MenuWorldPreviewer` instances (repo CLAUDE.md "Three Weapon Rendering Paths"); cosmetics hooks BOTH (`cosmetics_tweaker.lua:5310`, `:5346`, `:5455-5456`) |
| Button sounds | `host_window:_play_sound("Play_hud_select")` - forwards to the view state's `play_sound` | Do NOT resolve wwise off `music_world`; not registered in nested view contexts (memory `reference_vt2_ui_button_sound_use_window_play_sound`) |
| HUD components | `ingame_hud:component("<ClassName>")` from an `IngameUI.update` hook_safe | hud_ui classes are mission-lazy; string hooks fail at the keep with a red VMF error (memory `reference_vmf_hud_ui_class_hook_fails_at_keep`) - patch DATA or register lazily |

One hook per (Class, method) per mod, always - grep first (repo CLAUDE.md
non-negotiable 8). gut documents its whole-mod grep in each hook site
(`_gut_gui_material_guard.lua:295-297`, `_gut_menu_transition_probe.lua:34-38`).

---

## 4. Traps and crash classes

| # | Trap | Detail / canonical fix |
|---|---|---|
| 1 | **`create_screen_gui` C-fatal on non-resident material** (create time) | `World.create_screen_gui` hard-fatals - bypasses pcall AND xpcall (went through VMF's safe_call_nr and still killed the client). Cannot be caught; must be PRE-FILTERED via `Application.can_get("material", path)`. Fix: `_gut_gui_material_guard.lua` drop-filter with fail-open self-test. Memory `reference_vt2_create_screen_gui_missing_material_crash` |
| 2 | **Font material as create material** | `materials/fonts/arial` is a valid `Gui.text` FONT arg but NOT a create material -> instant fatal. Create with `materials/fonts/gw_fonts`; pass arial only to `Gui.text` (vanilla: `debug.lua:12` + `:81`). Burned gt #293/#295; fixed gt_dev `_gt_bot_teleport_lab.lua:1100`; **still live in gt STABLE `:897`** (see §5) |
| 3 | **Keep-only Gui material drawn mid-mission** (draw time) - BUG_CLASSES.md §23 | `Material 'X' not found in Gui` at `ui_passes.lua` texture draw (~`:134-194`) or `UIRenderer.draw_video` -> `Gui.video` (`ui_renderer.lua:1296` decompiled / `:1345` shipped) = hard CTD. Cause: `ingame_ui_settings.lua` appends whole groups only `if is_in_inn` (`:582-614`). Fix = BOTH layers: inject-when-resident (`UIRenderer.create` hook) + skip-the-widget at creation site. Canonical `_gut_gui_material_guard.lua` + `_gut_mission_map.lua` (#155/#80/#336) |
| 4 | **ShadingEnvironment.blend AV: undefined VARIATION** - BUG_CLASSES.md §22 | Mission-substituted preview world receives a variation request (`weapons_default_01`) its env doesn't define -> native 0xc0000005, uncatchable. Pin via `_update_environment` hook forcing `force_default = true` when the world env lacks the variation (`cosmetics_tweaker.lua:2751`, cim `:2298`); pick substitute env by residency, fallback `environment/blank` |
| 5 | **Raw options materials on a borrowed renderer** | `checkbox_checked`, `rect_masked`, `highlight_texture` etc. exist ONLY in `options_view_definitions.lua`, in no atlas -> `Material not found in Gui` when reused in a mod view. Build rows from `rect`/`border` passes + atlas-backed textures (`matchmaking_checkbox`, `slider_thumb` in `gui_settings_atlas.lua`); draw on `ingame_ui_context.ui_renderer`, not ui_top_renderer. Memory `reference_vt2_options_widgets_raw_materials`; canonical `_mod_tweaker_definitions.lua` |
| 6 | **hotspot pass without `style_id`** | Hit area falls back to the scenegraph NODE size; widgets sharing a `{1,1}` anchor node get 1x1-pixel click targets, silently. Always `{ pass_type="hotspot", content_id="hotspot", style_id="hotspot" }` with real `{w,h}`+offset in `style.hotspot` (`ui_passes.lua:4224`; memory `reference_vt2_options_widgets_raw_materials`, gut v0.2.34-dev) |
| 7 | **Child-window `update` fires before widgets exist** | `_widgets`/`_widgets_by_name` nil at random from a `HeroWindowX.update` hook. Drive from the parent state's `update` (memory `reference_vt2_widget_timing_pattern`; cim v0.7.57->58) |
| 8 | **`UIWidget.init` fixed `pass_data`** | In-place pass appends on a live widget desync `passes` vs `pass_data` -> re-init the widget (issue #313; `ui_widget.lua:19-26`; memory `reference_vt2_optionsview_synthesized_cb_takeover`) |
| 9 | **Unguarded `on_exit` in `IngameUI.destroy`** | A custom view open across IngameUI teardown without `on_exit` = crash (`ingame_ui.lua:234-240`) |
| 10 | **Copy-based class inheritance defeats base-class hooks** | `class.lua:51-57` copies methods at definition time; hook `MenuWorldPreviewer`, not `HeroPreviewer` (repo CLAUDE.md; burned wt v0.12.16) |
| 11 | **hud_ui classes lazy-load in-mission** | String hooks on them at the keep -> `trying to hook object that doesn't exist` ERROR + inert fix. Patch boot-global DATA (e.g. `DeusThemeSettings`) or lazy-register (memory `reference_vmf_hud_ui_class_hook_fails_at_keep`; BUG_CLASSES.md §1b for the generic dead-hook class) |
| 12 | **Input re-route under an open menu** | Blocking devices / swapping services while a menu is open without restoring on every exit path soft-locks (BUG_CLASSES.md §20; `exit_menu` unblock `ingame_ui_settings.lua:506-519`) |
| 13 | **Level-less preview viewport renders black + trails** | A viewport with nil level_name never clears the framebuffer - animated glow "bleeds". Mid-mission backdrop recipe: async-load `resource_packages/levels/ui_inventory_preview`, gate on `Managers.package:has_loaded`, mount `levels/ui_inventory_preview/world` + env `environment/ui_inventory_preview` (`hero_window_character_preview_definitions.lua:226-227`; memory `reference_vt2_keep_only_gui_materials`, #336) |
| 14 | **Repeat-transition guard eats re-opens** | `handle_transition` drops a transition equal to `_previous_transition` (`ingame_ui.lua:934-938`) - a custom "open my view" transition fired twice in a row silently no-ops; route exits through a DIFFERENT transition (gut exits via `"ingame_menu"`/`"hero_view"`/`"exit_menu"`) |
| 15 | **Decompiled-vs-shipped line drift** | Crash logs cite shipped lines (`ui_renderer.lua:1345`); the decompiled repo differs by up to ~50 lines in big files. Match by function name, not line |

---

## 5. Implications for our mods - concrete improvements

1. **[P1 - promotion-stranded crash fix] gt STABLE still creates its debug GUI
   with a font material.**
   `general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua:897`
   calls `World.create_screen_gui(world, "material", FONT_MTRL, "immediate")`
   with `FONT_MTRL = "materials/fonts/arial"` (`:849`) - trap §4.2, a
   guaranteed C-fatal whenever the bot-lab GUI spins up on stable gt. gt_dev
   already fixed it (`general_tweaker_dev/.../_gt_bot_teleport_lab.lua:985`
   comments + `:1100` creates with the gw_fonts material). Stable is read-only
   (dev-only edit doctrine) - this needs surfacing for promotion, exactly the
   #278-style stranded-fix failure mode `tools/promote/promotion-status.ps1`
   exists to catch.

2. **[P2 - hook the engine's registration surface instead of racing it] gut's
   view attach leans on a timing-fragile `setup_views` hook.**
   `gui_tweaker_dev/.../gui_tweaker_dev.lua:1316-1318` hooks
   `IngameUI.setup_views` but its own comment (`:1084-1089`) records that the
   post-Versus timing makes it silently bail, leaving the lazy attach inside the
   transition closure (`:1240-1243`) as the only reliable path. The
   engine-idiomatic alternative: append a synthetic entry to a
   `DLCSettings.<slot>.ui_views` list - `views_function` iterates DLCSettings
   AT EVERY IngameUI INIT (`ingame_ui_settings.lua:745-764`) and instantiates
   `_G[class_name]:new(ingame_ui_context)` with duplicate fasserts and
   inn/mechanism filters for free, no timing race. The transitions
   `package.loaded` mutation must stay (the DLC transition merge at
   `ingame_ui_settings.lua:885-895` ran at boot, before mods load), but the
   setup_views hook + `_attach_view`'s synthesized-context fallback
   (`:1094-1102`) could be retired.

3. **[P2 - dead per-frame hook riding the widget-timing trap] cim_dev's
   disabled standard-forge buttons still hook a child window's `update`.**
   `crafting_in_modded_dev/.../standard_forge.lua:1730-1738` hooks
   `HeroWindowCrafting.update`; the feature is permanently off
   (`_STD_FORGE_BTNS_ENABLED = false`, `:1725`), so the body is a per-frame
   no-op - and if ever re-enabled it would re-enter the exact
   child-window-update widget-timing trap (§4.7) that burned cim v0.7.57.
   Either delete the hook (keep the helpers) or re-route the driver through the
   parent state's `update` like the Athanor side already does
   (`crafting_in_modded_dev.lua:4078`).

4. **[P2 - chat-facing noise from UI hooks in a public mod]
   cosmetics_tweaker's glow-picker hook tracer echoes to chat.**
   `cosmetics_tweaker/.../cosmetics_tweaker.lua:9575-9581` (`_glow_hook_trace`)
   fires `mod:echo` on the first fire of each of five window hooks - user-visible
   chat spam in a shipped public mod (BUG_CLASSES.md §17), and `mod:info` is
   invisible with mod-logging off anyway (repo CLAUDE.md non-negotiable 9).
   Engine-idiomatic: `printf` one-shot, no echo.

5. **[P2 - silent input-service failure path] ModTweakerView swallows
   `create_input_service` errors.**
   `gui_tweaker_dev/.../_mod_tweaker_view.lua:64-69` wraps service creation in
   a bare `pcall`; on failure `input_manager:get_service("gut_mod_tweaker")`
   returns nil (`input_manager.lua:788-794`), `update` then early-returns
   (`_mod_tweaker_view.lua:1883-1884`) and `input_service()` (`:1873-1875`)
   hands nil to `IngameUI._menu_blocking_information` (`ingame_ui.lua:770`) -
   the view opens dead with no log. Cheap hardening: printf on pcall failure
   and fall back to the `"ingame_menu"` service (already created at
   `ingame_ui.lua:89-92`), mirroring vanilla's FAKE_INPUT_SERVICE degradation
   (`hero_view.lua:107-109`).

6. **[P2 - pattern consolidation, do-when-touched] The Gui-material guard is
   gut-only but protects a repo-wide crash class.**
   `_gut_gui_material_guard.lua` is the only inject-when-resident /
   drop-unloadable `UIRenderer.create` hook in the repo; cim and cosmetics each
   carry their own narrower env/HDR mitigations
   (`crafting_in_modded_dev.lua:2108-2556`, `cosmetics_tweaker.lua:2643-2785`).
   That is correct per the one-hook-per-mod rule (hooks from DIFFERENT mods
   chain), but any future mid-mission keep-view feature in a non-gut mod must
   re-implement the residency gate - when that happens, copy the gut module
   wholesale (self-test interlock included) rather than a partial gate; a
   partial (layer-1-only or layer-2-only) fix is a known non-fix
   (BUG_CLASSES.md §23 "Ship both").

What our code already does RIGHT (do not "improve" away): borrowed-renderer +
own-scenegraph overlays instead of widget injection (`_glow_picker.lua`,
`_accessory_craft_panel.lua`); full-interface custom view with origin-capture
exit (`_mod_tweaker_view.lua`); cb_ takeover + UIWidget re-init for options rows
(`_gut_ckc_bridge.lua`); hooking BOTH previewer classes
(`cosmetics_tweaker.lua:5310/:5346`); parent-state update drivers
(`crafting_in_modded_dev.lua:4078`); atlas-safe row materials
(`_mod_tweaker_definitions.lua`).
