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
          pin(p.id, PinKind.Output) { text(PIN_LABEL[p.id], (text = "{p.name} ->")) }
      }
      link(l.id, (from = l.from_pin, to = l.to_pin))  // also link(id, from, to) positional
  }
  ```
  Snapshot payloads: node `{id, bbox, selected}`, pin `{id, kind}`, link `{id, from_pin,
  to_pin, selected}`, node_editor `{handle, last_context_kind, last_node/pin/link/
  background_context_menu}`. Built by the body, not reflected (the wrappers pass `null`
  state to finalize, so the hand-built payload survives verbatim).
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
  Pins are not selectable in imgui-node-editor.
- **Context menus are EVENTS, not scopes** (see Gotchas): `with_suspended() { … }` brackets
  Suspend/Resume (screen space), and inside it `show_node_context_menu(ctx, var nid&)` /
  `show_pin_context_menu(ctx, var pid&)` / `show_link_context_menu(ctx, var lid&)` /
  `show_background_context_menu(ctx, var canvas_pos&)` each return bool on a right-click and
  record the target onto the editor (surfaced in the node_editor payload as
  `last_context_kind` + `last_*_context_menu` for frames to come). The app decides what to
  render in response (a `popup_window`, a button, anything) — the boost owns telemetry, the
  app owns rendering.

## Live commands (`imgui_node_editor_live`)

Project-agnostic — target any graph by `editor` handle (`intptr(ctx)` from the snapshot) +
entity id: `move_node`, `select_node_cmd`, `select_link_cmd`, `add_link_cmd`,
`clear_pending_links_cmd`, `delete_node_cmd`, `delete_link_cmd`, `clear_pending_deletes_cmd`.
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
