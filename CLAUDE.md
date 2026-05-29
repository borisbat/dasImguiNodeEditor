# dasImguiNodeEditor project instructions

dasImguiNodeEditor is the daslang binding + boost-v2 wrapper layer for
[imgui-node-editor](https://github.com/thedmd/imgui-node-editor) (v0.9.3, vendored).
It is built **on top of [dasImgui](https://github.com/borisbat/dasImgui)** and mirrors
its conventions — `[widget]`/`[container]` macros, the snapshot/telemetry path, the
default-on raw-call lint, the `imgui_harness` lifecycle, dastest integration tests, and
the `daslang-live` HTTP driver. **Read dasImgui's `CLAUDE.md` first** for all of that
shared machinery; this file documents only what is node-editor-specific.

`STATE.md` is the live working-notes/status doc (design rationale, verified-live logs,
known bugs, roadmap). This file is durable instructions; defer to `STATE.md` for "why"
and current status.

## Modules

Registered in `.das_module` via `register_native_path("imgui", "<name>", …)`. A NEW
daslib module MUST get its own line there, or `require imgui/<name>` fails with
`error[20605] … file not found` — and adding one needs a full **`daslang-live` restart**
(the `.das_module` change is not picked up by `.das` auto-reload).

| Module | Require | Role |
|---|---|---|
| `imgui_node_editor_boost_v2` | `require imgui/imgui_node_editor_boost_v2` | **the v2 boost — what new code uses.** App-owned editor ctx, id-only `node`/`pin`/`link`/`node_editor`, queue-injectable create+delete, selection, context-menu events. Bundles the lint via `require imgui/imgui_node_editor_lint public`. |
| `imgui_node_editor_lint` | (bundled by boost_v2) | NODEEDITOR001 — bans raw `imgui_node_editor::*` in consumers (see Lint). |
| `imgui_node_editor_live` | `require imgui/imgui_node_editor_live` | project-agnostic `[live_command]`s targeting an editor by handle + entity id. |
| `imgui_node_editor_app` | `require imgui/imgui_playwright` chain | `with_node_editor_app(feature){…}` test driver (node-editor mirror of dasImgui's `with_imgui_app`). `public`, NOT `shared`. |
| `imgui_node_editor_boost` | `require imgui/imgui_node_editor_boost` | legacy v1 thin Begin*/End* wrappers; kept for back-compat. |

## Dev workflow

- **Junction root `D:\Work\IMGUI`** with `modules\dasImgui` → `D:\DASPKG\dasImgui` and
  `modules\dasImguiNodeEditor` → `D:\DASPKG\dasImguiNodeEditor`. Edit source under
  `D:\DASPKG\…`; compile/run/lint with **`-project_root D:/Work/IMGUI`** (MCP tools:
  `project_root: "D:/Work/IMGUI"`).
- **C++ build:** `cmake --build D:/DASPKG/dasImguiNodeEditor/_build --config Release -j 64`
  (configure once with `-DDASLANG_DIR=D:/Work/daScript`). **dasImgui must be built first**
  (sibling under the same parent — the node-editor C++ links `dasModuleImgui`). **Shut down
  `daslang-live` before relinking** — it holds `dasModuleImguiNodeEditor.shared_module` open.
- **daslang-live auto-reloads on `.das` save.** A restart IS needed for: a new `.das_module`
  module, CLI-flag changes, and one-time-`init()` changes (the `EditorContext` + module
  globals survive reload, so first-run-gated code won't re-fire).
- **Inspect via live commands, not OS screen grabs.** `screenshot` (framebuffer→PNG),
  `imgui_snapshot` (widget tree), and `editor_dims` are ground truth. The `screenshot`
  command is accurate — do not blame it.

## Running the example

```
daslang-live -project_root D:/Work/IMGUI \
    modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das
```

(MCP: `live_launch` with `file` = `D:/DASPKG/dasImguiNodeEditor/examples/node-editor/shader_graph.das`,
`project_root` = `D:/Work/IMGUI`.) The example is the canonical reference for every API below.

## boost-v2 API (the surface to use)

All entry points take the app-owned `EditorContext?` (`ctx`). An app may show N graph
windows; the ctx is a handle the app creates/owns. `intptr(ctx)` (uint64) is the stable
editor id that crosses the live/JSON boundary; `handle_to_editor(uint64)` reverses it.

- **Lifecycle:** `create_node_editor() : EditorContext?` / `destroy_node_editor(ctx)`
  (create in `init`, destroy in `shutdown`). Settings/JSON persistence is deliberately off.
- **Editor + entities** (call forms as in `shader_graph.das`):
  ```
  node_editor("name", (editor = ctx, size = float2(0.0, 0.0))) {
      node(n.id, (color = tint)) {                 // color tuple optional → editor default
          text(NODE_TITLE[n.id], (text = n.title))  // indexed text — see Gotchas
          pin(p.id, PinKind.Input)  { text(PIN_LABEL[p.id], (text = "-> {p.name}")) }
          // pin pivot tuple optional — place the link-attach point on the pin edge:
          pin(p.id, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) { … }
      }
      node_group(g.id, (size = float2(220.0, 160.0))) { text(GROUP_TITLE[g.id], (text=g.title)) }
      link(l.id, (from = l.from_pin, to = l.to_pin))  // also link(id, from, to) positional
  }
  ```
  Snapshot payloads: node/node_group `{id, bbox, selected, z}` (a group is geometrically a
  node — same lazy `node_payload`), pin `{id}` (imgui-node-editor exposes no pin-kind query),
  link `{id, from_pin, to_pin, selected}`, node_editor `{handle, last_context_kind,
  last_node/pin/link/background_context_menu, last_new_node_drag_*}`. Built lazily at snapshot
  via the entry's `serialize` hook (re-derived from editor + id), not stored per frame.
- **Node geometry is editor-owned.** `node.pos` is an INITIAL seed only — push it once via
  `set_node_position(ctx, id, pos)` then never read it back; the editor owns position after.
- **Create (queue-injectable):** `begin_create(ctx){…}` + `query_new_link(ctx, var from&,
  var to&) : bool` + `accept_new_item(ctx) : bool` / `reject_new_item(ctx)`. Each also
  serves a link queued by `enqueue_new_link(ctx, from, to)` (the `add_link_cmd` backend), so
  the same handler the mouse drives also replays queued links. The queue entry is consumed on
  the app's DECISION (accept or reject), NOT at end-of-frame — calling neither keeps the
  offer alive across frames (a "pending link" indication). `clear_pending_links(ctx)` flushes.
- **Delete (queue-injectable, PER-KIND):** `begin_delete(ctx){…}` + `query_deleted_link(ctx,
  var lid&)` / `query_deleted_node(ctx, var nid&)` + `accept_deleted_link(ctx)` /
  `accept_deleted_node(ctx, delete_dependencies=true)` + `reject_deleted_link/node`. Unlike
  create, delete is a SINGLE-FRAME `while`-enumeration, so the queue is **pop-on-QUERY**.
  `clear_pending_deletes(ctx)` flushes.
- **Selection:** `get_selected_nodes(ctx) : array<NodeId>` / `get_selected_links(ctx)`,
  `select_node(ctx, id, on)` / `select_link(ctx, id, on)` (`on`=append), `clear_selection(ctx)`.
  Pins are not selectable in imgui-node-editor. `get_ordered_node_ids(ctx) : array<NodeId>`
  enumerates draw order (back-to-front).
- **Groups / comment boxes:** `node_group(id, (size=…)){…}` — a pin-less node: the body
  renders first (its title is the header), then `Group(size)` lays the box below it; child
  nodes dragged onto it move with it. `size` is a ONE-TIME seed (like node position) — once the
  node is a group the editor owns its bounds and ignores the passed size on later frames, so
  `set_group_size(ctx, id, size)` is the resize path (mutating the app-side size alone won't
  resize). First-class telemetry entity (kind `node_group`, distinct path `node_group_{id}`,
  reuses `node_payload`). Named `node_group` (NOT `group`) to avoid colliding with imgui's
  `BeginGroup`/`EndGroup` `group` container.
- **Node ops + view (transient — no snapshot state, but live-drivable):**
  `center_node_on_screen(ctx, id)`, `navigate_to_selection(ctx, zoom_in=false, duration=-1.0)`,
  `restore_node_state(ctx, id)`, `set_node_z_position(ctx, id, z)` (z DOES reflect — folds into
  `node_payload`), `get_node_position(ctx, id)` (geometry read peer of `set_node_position` — use
  it to capture a layout post-block, e.g. a clipboard copy). All bracket `SetCurrentEditor`
  (callable outside the draw loop); the navigation pair may share `NavigateToContent`'s DPI quirk
  (Gotchas #5).
- **Rendering config:** `with_style_var(StyleVar, value){…}` (float/float2/float4 overloads)
  brackets PushStyleVar/PopStyleVar; `with_style_color(StyleColor, color){…}` is its color peer
  (PushStyleColor/PopStyleColor — use it for any slot beyond NodeBg, which `node()`'s `color` arg
  already covers). `with_node_background_drawlist(id) $(var dl){…}` hands a node's background draw
  list for custom art — **call it AFTER the node()/group() block**, not inside (Gotchas #8).
  `group_hint(id) $(var fg; var bg) : bool` draws an off-screen group-label overlay; it self-gates
  (returns false / block skipped unless the canvas is zoomed out and `id` is a group), so call it
  unconditionally per group. Must run inside `node_editor()`, NOT inside `with_suspended`. The hint
  draw lists swap R/B for asymmetric colors — use near-grey label tints (Gotchas #10).
- **Theme:** `require imgui/imgui_node_editor_theme_daslang` → `apply_daslang_node_editor_style(ctx)`
  paints the canvas (`ed::Style`) warm-dark + amber to match the ImGui `apply_daslang_theme`. Call
  once after `create_node_editor`. The ImGui theme alone does NOT touch the canvas (node-editor keeps
  a separate `ed::Style`).
- **Per-pin geometry:** `pin()` takes `pivot_alignment` / `pivot_size` / `pivot_scale` (each
  sentinel `x < 0` = keep editor default) → PinPivotAlignment/Size/Scale, placing + sizing the
  link-attach point.
- **Context menus are EVENTS, not scopes** (see Gotchas): `with_suspended() { … }` brackets
  Suspend/Resume (screen space), and inside it `show_node_context_menu(ctx, var nid&)` /
  `show_pin_context_menu(ctx, var pid&)` / `show_link_context_menu(ctx, var lid&)` /
  `show_background_context_menu(ctx, var canvas_pos&)` each return bool on a right-click and
  record the target onto the editor (surfaced in the node_editor payload as
  `last_context_kind` + `last_*_context_menu` for frames to come). The app decides what to
  render in response (a `popup_window`, a button, anything) — the boost owns telemetry, the
  app owns rendering.
- **Clipboard / edit shortcuts are EVENTS** (same shape as context menus): shortcuts are ON by
  default (`create_node_editor`; toggle with `enable_shortcuts(ctx, on)`). `with_shortcuts(ctx) { … }`
  brackets BeginShortcut/EndShortcut (run it INSIDE `node_editor()`, NOT inside `with_suspended`);
  inside, branch on `accept_copy` / `accept_cut` / `accept_paste` / `accept_duplicate` /
  `accept_create_node` (each true the frame that chord fired, records `last_shortcut_action` +
  `last_shortcut_context_size` on the editor). The editor owns NO clipboard content — the app
  serializes the target set (`get_action_context_nodes(ctx)` / `…_links`, or its selection) on
  copy/cut and recreates on paste; topology stays app-owned. `enqueue_shortcut(ctx, kind)` (kind ∈
  cut/copy/paste/duplicate/create_node) + `clear_pending_shortcuts` replay a shortcut through the
  same accept handler a real chord hits — the drivable/testable rail (native key-chord synth is
  finicky; injection is deterministic). The `accept_*` only flag the action — do the actual
  clipboard work AFTER the `node_editor()` block (bracketed `get_selected_nodes`/`spawn`/`select`
  null the current editor mid-frame; see the demo's `handle_shortcut_action`, the flag-then-act
  pattern shared with `g_request_navigate`).

## Live commands (`imgui_node_editor_live`)

Project-agnostic — target any graph by `editor` handle (`intptr(ctx)` from the snapshot) +
entity id: `move_node`, `select_node_cmd`, `select_link_cmd`, `add_link_cmd`,
`clear_pending_links_cmd`, `delete_node_cmd`, `delete_link_cmd`, `clear_pending_deletes_cmd`,
`new_node_drag_cmd`, `flow_cmd`, `center_node_cmd`, `navigate_to_selection_cmd`,
`restore_node_state_cmd`, `set_node_z_cmd`, `set_group_size_cmd`, `ordered_node_ids_cmd`,
`clear_selection_cmd`, `shortcut_cmd`, `clear_pending_shortcuts_cmd`, `enable_shortcuts_cmd`.
For synth mouse/keyboard use dasImgui's commands — prefer the high-level
`imgui_mouse_click_at {x, y, button}` (button `1` = right-click) and `set_user_control
{enabled:false/true}` to cleanly own input during automation.

## Lint (`imgui_node_editor_lint`)

**NODEEDITOR001** — default-on, bans raw `imgui_node_editor::*` calls outside the curated
`ALLOWED_NE` allow-list, so the wrappers (create/delete queue injection, selection,
lifecycle) can't be bypassed. Per-file opt-out: `options _allow_node_editor_native = true`
(the boost/lint/live modules carry it themselves). To allow a new raw read, extend
`ALLOWED_NE` in `daslib/imgui_node_editor_lint.das`; to expose a new feature, wrap it.

## Tests + CI

`tests/integration/*.das` via `dastest` + `with_node_editor_app`. Run **headless** (spawned
daslang-live subprocesses else pop real windows and flake), cwd at the node-editor root.
Single file: `daslang -load_module D:/DASPKG/dasImgui -load_module D:/DASPKG/dasImguiNodeEditor
dastest.das -- --run modules/dasImguiNodeEditor/tests/integration/<t>.das --headless`. Sweep
stale `daslang`/`daslang-live`/`dastest` procs between runs (port 9090 reuse). CI:
`.github/workflows/tests.yml` (ubuntu/macos/windows; `daspkg install ../dasImgui` THEN
`../dasImguiNodeEditor` — dependency order).

**Test helpers (`imgui_editor_playwright`)** — layered on dasImgui's `imgui_playwright`
(re-exported, so `require imgui/imgui_editor_playwright public` is all a test needs beyond
`imgui_node_editor_app` for `with_node_editor_app`). `ne_open(app, canvas)` waits for the
canvas + returns an `EditorSession {app, handle, canvas}`; the `ne_*` helpers inject the
handle into the editor-targeted commands (`ne_select_node`/`ne_add_link`/`ne_shortcut`/
`ne_delete_node`/…), read the snapshot (`ne_node`/`ne_node_exists`/`ne_payload`/`ne_node_count`/
`ne_snapshot`), and wait (`ne_wait_widget`/`ne_wait_payload_str`/`ne_wait_shortcut`). Prefer
these over hand-threading the handle + raw `post_command`/`find_widget`. Keep distinct command
POSTs lean (the Windows libhv ~16-POST/subprocess ceiling); snapshot polling inside the waits
doesn't count against it. The module is `public` (not `shared`) — it requires the non-shared
`imgui_playwright`, and a `shared` module can't require a non-shared one (error 20115).

**Demo editor-realism behavior** (`shader_graph.das`, app-owned topology — mirror in real
consumers): links are normalized so `from_pin` is always the output; `can_add_link` rejects
self-loops, duplicate output→input pairs, and cycle-forming links (a downstream reachability
walk keeps the graph a DAG); a new link to an already-fed input REPLACES the old one (inputs
are single fan-in). The clipboard copies node kinds + RELATIVE positions + the links internal
to the selection (remapped by node-index + pin-slot); paste lands at the cursor preserving
layout, duplicate offsets near the originals.

## Gotchas

1. **Loop-rendered stateful widgets need the INDEXED `text` form.** `text("foo")` auto-emits
   ONE state global per source line; rendered in a loop (e.g. a node title or pin name per
   node), every iteration stomps that one cell, so the snapshot `value` collapses to the LAST
   iteration's text (all node titles read the last node's title). The RENDER is correct — only
   telemetry collapses. Fix: declare a module-scope `table<int; NarrativeState>` and key by id:
   `var NODE_TITLE : table<int; NarrativeState>` then `text(NODE_TITLE[n.id], (text = n.title))`.
   This is dasImgui doctrine (its `CLAUDE.md` "indexed widget tables"; `data_table.das`/
   `app_log.das` use it). The `shader_graph.das` example keys node titles by `n.id` and pin
   labels by `p.id`.
2. **`harness_apply_synth_io()` must be called each frame** (between `harness_begin_frame` and
   `harness_new_frame`) or synth IO (`imgui_mouse_*`/`imgui_key_*`/the live commands) silently
   never drains — synth right-clicks become pans, menus never open. The warning is stdout-only
   (invisible via the MCP response). The example calls it; any harness app you drive needs it.
3. **Context menus are events, not scopes.** `show_*_context_menu` only detects + records the
   target; it does NOT open a popup. The app opens whatever UI it wants in response and reads
   the target from the editor payload (`last_context_kind` / `last_*_context_menu`) — which
   stays observable in the snapshot for frames after the fire, with no user-land plumbing.
4. **Send a synth gesture as ONE atomic timeline.** Use `imgui_mouse_click_at` (or a single
   `imgui_mouse_play` move→press→release with `t_ms`), never separate `imgui_mouse_pos` +
   `imgui_mouse_click` round-trips — the gaps let real input interleave and corrupt the
   press position (a click becomes a drag/pan). `set_user_control{enabled:false}` fully
   suppresses real input so synth owns the window during automation.
5. **`NavigateToContent` is DPI-broken** under the harness's `GLFW_SCALE_TO_MONITOR` (it scales
   the view by the monitor content scale + pans off-screen). Currently disabled in the example.
   See `STATE.md` for the root-cause analysis.
6. **`handle_to_editor` blindly reinterprets a uint64 → pointer** — a bad handle crashes. Fine
   for a live dev tool (the handle comes from a snapshot); validate via a registry if hardened.
7. **pin/link `bbox` is zero** — imgui-node-editor exposes no pin/link geometry query (node only).
8. **`with_node_background_drawlist` must be called AFTER the `node()`/`group()` block**, not
   inside it. A node's draw channels only exist once it's fully built (post-`EndNode`); calling
   `GetNodeBackgroundDrawList` mid-body hits an unallocated `ImDrawListSplitter` and crashes
   (`SetCurrentChannel` null-write). The example draws the output-node accent after its block,
   still inside `node_editor()`. (The blueprints reference app does the same.)
9. **`group` is taken by imgui** (`BeginGroup`/`EndGroup`, pulled in via `require imgui public`).
   The node-editor group entity is `node_group` — defining a `group` here is `error[30607]
   ambiguous_macro`. Same rule for any future entity whose natural name collides with a dasImgui
   widget/container macro: prefix it (`node_*`).
10. **Group-hint draw lists swap R/B for asymmetric colors.** Inside `group_hint(id)`, art drawn
    into the foreground/background hint draw lists comes out with R and B channels swapped vs
    `rgba()`'s packing (amber `(232,161,58)` renders blue) — a vendored color-format quirk in the
    hint splitter path. Near-grey tints are swap-invariant; the example labels groups in cream.
    `GetGroupMin`/`GetGroupMax` inside a hint are SCREEN-space (not canvas-space).
11. **`GetActionContextSize` ≠ the action's id lists under injection.** `GetActionContextSize`
    reads the editor's internal `m_Context`, populated only when a REAL chord ran (0 under the
    `enqueue_shortcut` injection rail), whereas `GetActionContextNodes`/`Links` read
    `GetSelectedObjects` (populated either way). The wrappers source the action's target set
    uniformly from the SELECTION (`GetSelectedObjectCount`) so `last_shortcut_context_size` +
    `get_action_context_nodes/links` agree for both real and injected actions. The accept_* must
    run with the editor current (inside `node_editor()`); the actual clipboard work goes AFTER the
    block (bracketed selection/spawn helpers would null the current editor mid-frame).
