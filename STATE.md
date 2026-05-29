# dasImguiNodeEditor — State of Affairs

Working notes for the in-progress port of dasImguiNodeEditor onto the **dasImgui v2 API**
(dasImgui is the template; goal is full parity — v2 wrappers, live, docs/Pages, tests, CI).

Last updated: 2026-05-29. **PRs #1–#5 MERGED to master; #6 (this branch
`bbatkin/node-editor-api-completion`) in progress.** All CI-green (ubuntu/macos/windows):
- **#1** — whole v2 surface: id-only node/pin/link + multi-editor app-owned ctx + move_node +
  selection + `selected` in snapshot; `imgui_node_editor_live` live commands; queue-injectable
  CREATE (begin_create/query_new_link/accept_new_item/reject_new_item) and DELETE (begin_delete +
  PER-KIND query/accept/reject _link & _node, separate queues+flags, pop-on-decision so reject
  pops); `imgui_node_editor_app` test driver; `test_topology.das`; `.github/workflows/tests.yml`.
- **#2** — node/pin/link/node_editor **migrated from hand-unrolled to `[widget]`/`[container]`
  `forward_argument`** (dasImgui's forward_argument feature). Entities are now first-class macro
  widgets; the id is the forwarded arg0.
- **#3** — node_editor lazy serialize payload (drops per-frame JV), call-form tests (tuple +
  non-tuple), raw-native lint `NODEEDITOR001`.
- **#4** — right-click context menus (events, not scopes) + all 5 node types via toolbar + context
  menu + the `harness_apply_synth_io()` synth-drain fix + the indexed-`text` snapshot-telemetry fix
  + `CLAUDE.md`.
- **#5** — node-creation-by-drag (`show_new_node_drag` + `enqueue_new_node_drag` + `new_node_drag_cmd`
  + filtered create-menu + connect-on-select) and link flow (`flow` one-shot pulse + `flow_cmd`);
  `test_new_node_drag.das` + `test_flow.das`.
- **#6** (this branch) — **groups + the non-telemetry rail backfill.** Telemetry: `node_group`
  entity (kind `node_group`, reuses node_payload) + `set_group_size`; z folds into `node_payload`.
  Non-telemetry: `with_style_var`, pin pivot config on `pin()`, `with_node_background_drawlist`
  (call after the node block), view ops `center_node_on_screen`/`navigate_to_selection`/
  `restore_node_state`/`set_node_z_position` + their live commands, `get_ordered_node_ids` +
  `ordered_node_ids_cmd`. Demoed in `shader_graph.das`; `test_node_group.das` + `test_node_ops.das`.
- **#7** (this branch — `bbatkin/node-editor-daslang-style`) — **canvas theme + the last small
  non-telemetry rails.** New module `imgui_node_editor_theme_daslang` (`apply_daslang_node_editor_style`
  paints `ed::Style` warm-dark + amber to match the ImGui `apply_daslang_theme` — the ImGui theme alone
  leaves the canvas the library's default). Plus `with_style_color` (color peer of `with_style_var`),
  `pin()` `pivot_scale` (completes the pivot trio), and `group_hint(id) $(var fg; var bg)` (off-screen
  group-label overlay; self-gates on zoom). All wired into `shader_graph.das` + covered by
  `test_render_config.das`. Closes the deferred niche rendering items; only clipboard/shortcuts remains.
- **#8** (this branch — `bbatkin/node-editor-shortcuts`) — **clipboard / edit shortcuts — the LAST
  native rail.** Events (same shape as context menus): `with_shortcuts(ctx)` brackets
  BeginShortcut/EndShortcut; `accept_copy`/`accept_cut`/`accept_paste`/`accept_duplicate`/
  `accept_create_node` each fire true on their chord + record `last_shortcut_action` /
  `last_shortcut_context_size` (telemetry). Shortcuts ON by default in `create_node_editor`
  (`enable_shortcuts` toggles). Injection rail `enqueue_shortcut(ctx, kind)` + `shortcut_cmd` /
  `clear_pending_shortcuts_cmd` replay through the same accept handler (native chord synth is
  finicky → injection is the deterministic/testable path). `get_action_context_nodes/links` read
  the target set. The editor owns no clipboard CONTENT — the demo carries an app clipboard (copy
  captures selected node kinds, paste cascades, cut = copy+delete, duplicate = copy+paste), run
  post-block via the flag-then-act pattern. Also added `clear_selection_cmd`. Covered by
  `test_shortcuts.das` (inject duplicate + copy/paste, assert telemetry + node-count growth).
  **The native imgui_node_editor surface is now fully wrapped.** Remaining: non-native plumbing
  only (write-back editing, generalize `with_node_editor_app`, richer clipboard handling).
- **#9** (this branch — `bbatkin/node-editor-realism`) — **editor realism + test infra.** Made
  `shader_graph.das` behave like a real node editor (app-owned topology): link direction
  normalized (from=output), `can_add_link` rejects duplicates / self-loops / cycles (downstream
  reachability → DAG), new link to an occupied input REPLACES it (single fan-in); clipboard now
  copies node kinds + RELATIVE positions + the links internal to the selection (remapped by
  node-index + pin-slot), paste lands at the cursor preserving layout, duplicate offsets near the
  originals. New rail `get_node_position(ctx, id)` (bracketed geometry read, for copy). New test
  infra: **`imgui_editor_playwright`** (`EditorSession` + `ne_*` helpers over imgui_playwright) —
  all 9 existing tests refactored onto it. New live command `spawn_node_cmd` (demo, for
  deterministic id-based tests). New tests `test_link_rules.das`
  (dedupe/self-loop/cycle/replace) + `test_clipboard.das` (copy-links + preserved layout). 11
  integration tests green locally. Stacked on #8 (rebases to master when #8 merges).

## Key files

- `D:\DASPKG\dasImguiNodeEditor\daslib\imgui_node_editor_boost_v2.das` — **the v2 boost** (module
  `imgui_node_editor_boost_v2`). All the new API: app-owned editor ctx (create/destroy/
  handle_to_editor/node_editor/set_node_position), id-only `node()`/`pin()`/`link()`, queue-
  injectable CREATE + DELETE wrappers, ctx-based selection. This is what new code requires.
- `D:\DASPKG\dasImguiNodeEditor\daslib\imgui_node_editor_boost.das` — **legacy v1** (module
  `imgui_node_editor_boost`). Only the thin block-bracket wrappers (Begin/BeginNode/BeginPin/
  BeginCreate/BeginDelete) over raw imgui-node-editor Begin*/End*. Kept for back-compat; mirrors
  dasImgui's daslib `imgui_boost` (v1) vs `imgui_boost_v2` split (Boris chose same-dir / new file
  instead of a widgets/ dir).
- `D:\DASPKG\dasImguiNodeEditor\daslib\imgui_node_editor_live.das` — module
  `imgui_node_editor_live`. Project-agnostic `[live_command]`s that target an editor by its
  handle (= `intptr(ctx)` from the node_editor snapshot payload) + an entity id, so they drive
  ANY graph: `move_node`, `select_node_cmd`, `select_link_cmd`, `add_link_cmd`,
  `clear_pending_links_cmd`, `delete_node_cmd`, `delete_link_cmd`, `clear_pending_deletes_cmd`.
  Requires `imgui/imgui_node_editor_boost_v2` + `live/live_commands`. **All three modules are
  registered in `.das_module` via `register_native_path("imgui", "<name>", "{project_path}/
  daslib/<name>.das")`** — a NEW daslib module MUST get its own line there or `require imgui/<name>`
  fails with `error[20605] ... file not found`. Adding a new module also needs a full
  `daslang-live` RESTART (the `.das_module` change isn't picked up by `.das` auto-reload).
- `D:\DASPKG\dasImguiNodeEditor\daslib\imgui_node_editor_app.das` — module
  `imgui_node_editor_app` (**`public`, NOT `shared`** — it requires `imgui/imgui_playwright`
  which is `public`/non-shared, and a `shared` module can't require a non-shared one → error
  20115). Test driver: `with_node_editor_app(feature){…}` — a node-editor-aware mirror of
  dasImgui's `with_imgui_app` that spawns daslang-live with `-load_module <dasImgui>` AND
  `-load_module <node-editor>` (dasImgui resolved as the sibling of the node-editor root) +
  resolves feature paths under the node-editor root. Reuses all of playwright's helpers
  (post_command/snapshot/wait_*/find_widget/wait_until_ready). MIGRATION: fold into a
  generalized dasImgui `with_imgui_app` (extra module roots) later, then drop this.
- `D:\DASPKG\dasImguiNodeEditor\src\dasIMGUI_NODE_EDITOR.main.cpp` — hand-edited C++ hook.
  Holds `CreateEditorNoSettings()` + its `addExtern` in `initMain()` + `aotRequire` fwd-decl.
- `D:\DASPKG\dasImguiNodeEditor\examples\node-editor\shader_graph.das` — **the canonical example**
  (moved INTO the package 2026-05-28 so CI ships it). Dev runs it via the junction:
  `daslang-live -project_root D:/Work/IMGUI modules/dasImguiNodeEditor/examples/node-editor/
  shader_graph.das` (from D:\Work\daScript cwd via `bin/Release/`). NOTE: the
  `D:\Work\daScript\examples\node-editor\` copy STAYS (Boris, 2026-05-28) until the port is 100%
  done, then a purpose-built main-repo example replaces it. The `D:\Work\IMGUI\examples\node-editor\`
  dev copy is redundant (left in place, not committed anywhere).
- `D:\DASPKG\dasImguiNodeEditor\tests\integration\test_topology.das` — first integration test
  (`dastest` + `imgui_node_editor_app`). Drives the example via the live commands, asserts on the
  snapshot: create link (`add_link_cmd`→link_14), delete link, delete node (cascade). Lean to stay
  under the Windows libhv ~16-POST ceiling. VERIFIED locally PASS both headed (run_test) and
  headless (`dastest -- --test … --headless`), ~10.5s.
- `D:\DASPKG\dasImguiNodeEditor\.github\workflows\tests.yml` — CI. Checks out daslang(master) +
  dasImgui + node-editor; builds daslang + base shared modules; `daspkg install ../dasImgui
  --global` THEN `../dasImguiNodeEditor --global` (dependency order — node-editor's C++ links
  dasModuleImgui); runs `dastest --test modules/dasImguiNodeEditor/tests/integration --headless`.
  ubuntu/macos/windows, fail-fast:false. **GREEN on all 3 OSes** (PR #1, run 26570402604). One CI
  round was lost to a CMakeLists bug: it linked `libDaScriptDyn.so` (single `lib`) but daslang names
  the Linux/macOS dynamic runtime `liblibDaScriptDyn.so`/`.dylib` — fixed to mirror dasImgui (APPLE
  branch + `liblib` name + `-fno-rtti` ABI match); Windows `.lib` was already correct.
- Vendored node-editor C++: `D:\DASPKG\dasImguiNodeEditor\imgui-node-editor\*.cpp/.h`.

## Dev workflow

- **Junction root** `D:\Work\IMGUI` with `modules\dasImgui` → `D:\DASPKG\dasImgui` and
  `modules\dasImguiNodeEditor` → `D:\DASPKG\dasImguiNodeEditor`. Edit module source in
  `D:\DASPKG\...`; compile/run with `-project_root D:/Work/IMGUI` (MCP: `project_root`).
- **C++ build:** `cmake --build D:/DASPKG/dasImguiNodeEditor/_build --config Release -j 64`
  (configure once with `-DDASLANG_DIR=D:/Work/daScript`). dasImgui must be built first
  (sibling under the same parent). **Shut down daslang-live before relinking** — it holds
  `dasModuleImguiNodeEditor.shared_module` open.
- **daslang-live auto-reloads on code save** — no restart for `.das` edits. Restart IS needed
  for: command-line flag changes, AND one-time-init changes (the EditorContext and module
  globals survive reload, so changes gated on first-run won't re-fire).
- **Inspect via live commands**, not OS screen grabs. `screenshot` (framebuffer→PNG),
  `imgui_snapshot` (widget tree), and the custom `editor_dims` are ground truth. The
  `screenshot` command is accurate — do not blame it.

## Working now — full graph is FIRST-CLASS via id-only `[widget]`/`[container]` entities

> Updated 2026-05-29: entities were initially hand-unrolled (the design walk below). PR #2
> migrated them to `[widget]`/`[container]` with `forward_argument` once dasImgui shipped that
> feature — same id-only/no-state-global semantics, now as first-class macro widgets. The
> rationale below still holds; only the mechanics changed (see "Entity mechanics now").

Converged design 2026-05-28 (Boris, walking conclusions):
1. **Graph data design doesn't matter to the editor.** It binds via `(addr, ti)` reflection /
   dispatch — works on any struct, any layout. The app models its graph however it likes; the
   editor is agnostic. Only coupling: the few values the editor feeds the C++ API (node id,
   link from/to), and even those can be explicit args.
2. **node/pin/link are VIEWERS, not editors (yet).** They render + register + serialize; data
   flows one way (data → snapshot). No write-back: dragging a node doesn't update app data;
   create/delete is still raw example code. Editing is a *separate* concern (next).
3. **NodeId is the editor's internal handle** (a pointer on the C++ side) — the editor owns
   node geometry. So `node(id){…}` needs ONLY the id. No app global table, no bound struct.
   The id-keyed-global-table I'd introduced existed *only* to satisfy the indexed macro's
   addr-getter (`def __widget_addr$…(k){ return addr(IDENT[k]) }` names a global because a
   fn-ptr can't capture). Drop the macro → drop the global table.

4. **Editor context is APP-OWNED — no singleton.** An app may show N graph windows, so the
   `EditorContext` is a handle the app creates/owns (like node ids). The boost takes `ctx` on
   every entry point. `intptr(ctx)` (uint64; `intptr` is in daslib/builtin, takes `void?`,
   returns uint64) is the stable unique editor id that crosses the live/JSON boundary —
   `handle_to_editor(uint64)` reinterprets it back. No name-map, no boost registry needed.

**Entity mechanics now (PR #2 — `forward_argument` macros, NOT hand-unrolled):** node/pin/link/
node_editor are `[widget(forward_argument=true)]` / `[container(forward_argument=true)]`. The id
is the forwarded arg0; the macro builds the path key `{kind}_{id}` at runtime (node_editor adds
`verbatim_path=true` → arg0 is the literal name). No state struct, no auto-emitted state global —
that's exactly what `forward_argument` is for. The body builds the payload and calls
`finalize_entity(...)` (`container_finalize(…, null, null)`) / `finalize_entity_leaf(...)` for the
`link` leaf — **null (state_addr, ti) is still the trick**: snapshot uses the hand-built
`entry.payload` verbatim (no reflection, no g_widgets meta to clobber it).
- `create_node_editor() : EditorContext?` / `destroy_node_editor(ctx)` — app lifecycle.
- `node_editor("name", (editor = ctx, size = float2(0,0))) { … }` — SetCurrentEditor(ctx)/Begin/
  End/SetCurrentEditor(null) + payload `{handle, last_*_context_menu …}`. Path component = name.
- `node(id, (color = …)) { … }` (color tuple optional), `pin(id, kind) { … }`,
  `link(id, (from = p1, to = p2))` (also positional `link(id, p1, p2)`).
- `set_node_position(ctx, id, pos)` — brackets SetCurrentEditor; the only node interaction.
- Payloads: node `{id, bbox, selected}` (bbox from `GetNodePosition`+`GetNodeSize`, selected
  from `IsNodeSelected` — editor owns both), pin `{id, kind}`, link `{id, from_pin, to_pin,
  selected}` (`IsLinkSelected`), node_editor `{handle, last_context_kind, last_node/pin/link/
  background_context_menu}`. Selection is queried during finalize (editor context is current
  inside the node_editor block) — both DRIVABLE (select_*_cmd) and OBSERVABLE (snapshot). Pins
  aren't selectable in imgui-node-editor.

**Selection / test infra (boost, all ctx-bracketed):** `get_selected_nodes(ctx) : array<NodeId>`
/ `get_selected_links(ctx) : array<LinkId>` (buffer of pointer-sized slots, read back via
intptr), `select_node(ctx, id, on)` / `select_link(ctx, id, on)` (on=append; SelectNode/
DeselectNode etc.), `clear_selection(ctx)`. The example adds a `toolbar()` (app-specific UI):
**Add Node** (add_node + set_node_position cascade-positioned), **Delete Selected Node**
(get_selected_nodes → remove_node), **Delete Selected Link** (get_selected_links → erase).
The `move_node` / `select_node_cmd` / `select_link_cmd` / `add_link_cmd` live commands are
project-agnostic and live in the `imgui_node_editor_live` module (take editor handle + id +
on/x,y/from,to); the example keeps only its app-specific debug commands (`navigate_to_content`,
`editor_dims`).

**Link creation (boost; queue-injectable, drivable via live):** `begin_create(ctx){…}` /
`query_new_link(ctx, var from_pin&, var to_pin&) : bool` / `accept_new_item(ctx) : bool` /
`reject_new_item(ctx)` mirror imgui-node-editor's BeginCreate/QueryNewLink/AcceptNewItem/
RejectNewItem, but each also serves a link queued by `enqueue_new_link(ctx, from, to) : bool` (the
`add_link_cmd` backend). The next frame replays the queued link through the SAME app create handler
the mouse drives → topology stays app-owned + genuinely bidirectional. `has_pending(h)` holds across
begin→query→accept/reject within a frame; the queue entry is consumed (popped) on the app's DECISION
— accept (pop + create) OR reject (pop + drop). Calling NEITHER keeps the offer alive across frames,
which is exactly how an app shows a "pending link" indication for N frames before committing (this is
why auto-consume-at-end-of-frame is WRONG — it'd drop the offer after frame 1). A queued link wins
over a live drag for that frame. Validity gates accept-vs-reject (called every frame); accept's bool
return gates the commit (true only on a live drag's release frame). `query_new_link` takes `int&`
out-params (the `int?`/`safe_addr` bridge hidden inside). `reject_new_item` returns void (matches C++
`RejectNewItem`); on a live drag it calls the real `RejectNewItem` so the editor draws the red
"won't connect" preview — NOT a nop. `clear_pending_links(ctx)` (live: `clear_pending_links_cmd`)
is the bulk/cancel flush (drop queued links without a per-link decision).

**Item deletion (boost; queue-injectable, drivable via live):** `begin_delete(ctx){…}` /
`query_deleted_link(ctx, var lid&) : bool` / `query_deleted_node(ctx, var nid&) : bool` /
`accept_deleted_link(ctx) : bool` / `accept_deleted_node(ctx, delete_dependencies=true) : bool` /
`reject_deleted_link(ctx)` / `reject_deleted_node(ctx)` (PER-KIND, decoupled) mirror
BeginDelete/QueryDeletedLink/QueryDeletedNode/AcceptDeletedItem/RejectDeletedItem; each also serves
deletions queued by `enqueue_delete_node(ctx,id)` / `enqueue_delete_link(ctx,id)` (backends of
`delete_node_cmd` / `delete_link_cmd`). **KEY DIFFERENCE from create:** delete is a SINGLE-FRAME
`while`-loop enumeration, not a multi-frame offer — native `QueryItem` drops every candidate within
the frame (auto-rejects undecided ones, [cpp:5069](imgui-node-editor/imgui_node_editor.cpp#L5069)).
So the queue is **pop-on-QUERY** (query hands out one queued item and removes it → advances the loop,
can't spin), NOT pop-on-decision. accept/reject still differ in OUTCOME (apply removal vs keep) via
`g_delete_servicing` (the bool the latest query sets). Queued deletions drain first, then native ones
(calling native QueryDeleted* after the queue empties is safe — it returns false when `!m_InInteraction`).
Reject is PER-KIND (`reject_deleted_link` / `reject_deleted_node`, both void → `RejectDeletedItem`).
`clear_pending_deletes(ctx)` (live: `clear_pending_deletes_cmd`) is the bulk/cancel flush.

Example (D:\Work\IMGUI\examples\node-editor\shader_graph.das) — app owns the cohesive Graph
(pins inline in nodes) AND the context `var g_ed : EditorContext?` (created in init, destroyed
in shutdown). `Node.pos` is INITIAL SEED ONLY — editor owns position after placement:
```
// NODE_TITLE / PIN_LABEL : table<int; NarrativeState> — indexed text() so loop-rendered
// titles/pin-names get a per-id telemetry slot (see "snapshot telemetry" below).
node_editor("shader_graph", (editor = g_ed, size = float2(0.0, 0.0))) {
    for (n in values(g.nodes)) {
        if (!key_exists(g_seeded, n.id)) { SetNodePosition(n.id, n.pos); g_seeded |> insert(n.id) }   // seed once, in-frame (per-node, not frame-0)
        node(n.id, (color = node_tint(n.kind))) {
            text(NODE_TITLE[n.id], (text = n.title))
            for (p in n.inputs)  { pin(p.id, PinKind.Input)  { text(PIN_LABEL[p.id], (text = "-> {p.name}")) } }
            for (p in n.outputs) { pin(p.id, PinKind.Output) { text(PIN_LABEL[p.id], (text = "{p.name} ->")) } }
        }
    }
    for (l in values(g.links)) { link(l.id, (from = l.from_pin, to = l.to_pin)) }
    begin_create(g_ed) {                       // create is WRAPPED (mouse OR queued link)
        var a = 0; var b = 0
        if (query_new_link(g_ed, a, b)) {
            if (a != 0 && b != 0) {            // validity gates accept-vs-reject (every frame)
                if (valid_link(g, a, b)) {     // output<->input only
                    if (accept_new_item(g_ed)) { add_link(g, a, b) }
                } else {
                    reject_new_item(g_ed)      // pop+drop (queued) / red preview (live drag)
                }
            }
        }
    }
    begin_delete(g_ed) {                       // delete is WRAPPED (Delete-key OR queued); PER-KIND accept
        var lid = 0
        while (query_deleted_link(g_ed, lid)) { if (accept_deleted_link(g_ed)) { g.links |> erase(lid) } }
        var nid = 0
        while (query_deleted_node(g_ed, nid)) { if (accept_deleted_node(g_ed)) { remove_node(g, nid) } }
    }
    // Right-click context menus — EVENTS, not scopes (Suspend/Resume island, screen space).
    // show_* only detect + record the target onto the editor (surfaced in the node_editor
    // payload as last_context_kind / last_*_context_menu); the APP renders the popup.
    with_suspended() {
        var nid = 0; var lid = 0
        if      (show_node_context_menu(g_ed, nid))       { g_ctx_node = nid; open_popup("ne_node_menu") }
        elif    (show_link_context_menu(g_ed, lid))       { g_ctx_link = lid; open_popup("ne_link_menu") }
        elif    (show_background_context_menu(g_ed, g_ctx_pos)) { open_popup("ne_bg_menu") }
        // … popup_window(BG_CTX, …) { menu_label(CREATE_TEX,…) → ctx_spawn(NodeKind.TexInput); … }
    }
}
// move_node (in imgui_node_editor_live): handle=input.editor (uint64);
//   ctx=handle_to_editor(handle); set_node_position(ctx, id, float2(x,y)).
//   NO graph write — editor owns geometry.
```

**VERIFIED 2026-05-28 via live commands (all driven through the snapshot's addressable paths):**
- Editor-named paths — `MAIN_WIN/shader_graph/node_5`, `…/node_5/pin_6`, `…/link_11`; node_editor
  payload `{name, handle}`; real node bboxes from the editor.
- `move_node {editor:handle, id:1, x:200, y:400}` → node_1 → (200,400)–(261,449), child text follows.
- `select_node_cmd {id:3, on:true}` → Tint shows the editor's orange selection highlight; then
  `imgui_click {target:"MAIN_WIN/:135:8"}` (Delete Selected Node) → node_3 + its pins + touching
  link cascaded out. `imgui_click MAIN_WIN/:128:8` (Add Node) → new node placed. `select_link_cmd
  {id:11}` + `imgui_click MAIN_WIN/:143:8` (Delete Selected Link) → link_11 removed. Full
  select→click→mutate chain works via live; buttons clickable through `imgui_click`.
- `add_link_cmd {editor:handle, from:2, to:7}` → injected through begin_create/query_new_link/
  accept_new_item → app's add_link wrote `link_14 {from_pin:2, to_pin:7}` to the Graph; appeared
  in snapshot ONCE (no dupes over ~1200 frames → pop-on-accept confirmed).
- batched `[add_link_cmd, clear_pending_links_cmd]` → snapshot shows NO link_14 (queue flushed
  before the next draw served it) → clear_pending_links confirmed.
- reject path: example validates output↔input only. `add_link_cmd {from:2, to:4}` (output→output)
  → rejected → dropped (snapshot ~1000 frames later: no new link). Then `add_link_cmd {from:2,
  to:7}` (output→input) → created `link_14`. The valid one creating PROVES reject popped the
  invalid one (else it'd stick at the queue front and block the valid one) → reject_new_item
  consumes the decision, no stuck queue.
- DELETE injection: `delete_link_cmd {id:13}` → link_13 removed (11,12 + all nodes intact).
  `delete_node_cmd {id:5}` → node_5 + its pins 6/7/8 + the links touching them (11,12) cascaded out
  via remove_node; nodes 1/3/9 remain. batched `[delete_node_cmd {id:9}, clear_pending_deletes_cmd]`
  → node_9 still present → clear_pending_deletes confirmed.

**The value-payload artifact is FIXED (PR #4), example-side.** It was never a core bug: the
plain `text("foo")` form shares ONE state global per source line, so loop-rendered titles/pin-names
collapsed to the last value in the snapshot (all titles "Texture"). Fix = the documented **indexed**
form `text(NODE_TITLE[n.id], (text = n.title))` / `text(PIN_LABEL[p.id], …)` with module-scope
`table<int; NarrativeState>` (dasImgui's loop-widget idiom — `data_table.das`/`app_log.das`). No
core/registry change; the deferred eager-vs-lazy registry-perf question (below) is moot for this
case. Verified: snapshot now reports per-node titles ("Texture"/"Tint"/"Multiply"/"Color Output"/
"Add") and per-pin labels correctly.

**Open notes:**
- pin/link `bbox` is zero — imgui-node-editor exposes NO pin/link geometry query (only node).
  Link bbox derivable from endpoint pins later.
- `handle_to_editor` blindly reinterprets a JSON uint64 → pointer (bad handle = crash). Fine
  for a live dev tool (handle comes from a snapshot); a boost-side editor registry could
  validate later.
- Live-reload re-runs `init()` here (the new `g_ed` got a live context after reload), so
  `create_node_editor` leaks the prior ctx on reload — dev-only, ignore.
- Generalization signal: **DONE (PR #2).** dasImgui's `forward_argument` `[widget]`/`[container]`
  is exactly the id-keyed, no-state-global, payload-built-by-body form — node/pin/link/node_editor
  are annotations again.
- **CANDIDATE MACRO (Boris, 2026-05-28):** live commands hand-write `input?["k"] ?? default`
  extraction per field. imgui's text-style widgets accept TWO input forms (regular positional +
  named-tuple); we likely want a similar macro that generates a live command's input extraction
  from a typed arg struct, supporting both forms. Deferred — note for later.
- **Reject → stuck queue: RESOLVED via `reject_new_item`** (not auto-consume). The queue entry is
  popped on the app's DECISION — accept OR reject. auto-consume (pop at end-of-frame regardless)
  was REJECTED by Boris: it breaks an app that shows a pending-link indication for N frames before
  committing (it'd drop the offer after frame 1). `clear_pending_links` remains the bulk/cancel
  flush, not the rejection mechanism.

## NEXT TASK

DONE: id-only entities (now `forward_argument` macros, PR #2); multi-editor app-owned ctx;
move_node; selection API (get_selected / select / clear); `selected` in node+link payloads; full
topology-edit half — queue-injectable CREATE (begin_create/query_new_link/accept_new_item/
reject_new_item) + DELETE (begin_delete + PER-KIND query/accept/reject _link & _node) with live
commands; lazy node_editor payload + call-form tests + `NODEEDITOR001` lint (PR #3); CI green on 3
OSes; right-click context menus (events) + all-5-node-type creation (toolbar + context menu) +
`harness_apply_synth_io()` synth-drain fix + indexed-`text` telemetry fix + `CLAUDE.md` (PR #4,
this branch).

Open candidates (Boris's call on shape — propose before implementing):
- graph-level `[live_command]` for `add_node` (position + kind; app-specific-ish) if useful.
- Tier-2 node-editor API backlog: node-creation-by-drag (QueryNewNode), groups/comment nodes, pin
  pivot config, flow animation, clipboard/shortcuts (see the `project_node_editor_api_backlog` memory).
- **write-back / editing** — node/pin/link are still VIEWERS (data → snapshot one-way; dragging a
  node doesn't update app data). Editing is the next big concern.
- CANDIDATE MACRO for live-command input extraction (see Open notes).

## DEFERRED (perf-gated): GENERAL registry eager-vs-lazy + visible-through-live

**Update 2026-05-29: the node-editor's snapshot artifact is FIXED** example-side (PR #4, indexed
`text` — see "value-payload artifact is FIXED" above). What stays deferred is the GENERAL dasImgui
question: should the registry eager-capture per-instance payloads so even *non-indexed* loop-rendered
stateful widgets report correct telemetry? dasImgui doctrine answers "use the indexed form," so this
is low priority. Boris's original call stands: **do NOT touch the registry until measured** — write a
perf test (eager registry-populate vs not) first; hypothesis is the eager part is meaningless vs
rendering cost. "not until then."

The mechanics (why non-indexed loop widgets collapse, for reference): `imgui_snapshot` reports
tree/paths/bboxes **correctly**, but per-leaf `"value"` payloads are wrong for repeated call sites in
a loop — every `text()` title leaf serializes `"Texture"`, every input pin `"-> B"`, every output pin
`"RGBA ->"`. Root cause (CONFIRMED by reading the runtime):
- The `[widget]` macro emits ONE state global per call site. In a loop every iteration writes
  that shared global (`state.value := text`), so it ends holding the LAST instance's value.
- `widget_finalize` (`imgui_boost_runtime.das:1042`) records a per-path `WidgetEntry` into
  `g_registry[path_key]` (so paths/bboxes are per-path-correct) but stores `state_addr` =
  the **shared global's address** into `g_widgets[path_key]`.
- At snapshot, `state_payload_jv(meta.state_addr, ti)` (`:639`) reads that shared global via
  `sprint_json_at` → all path-instances report the one last-written value.
- Two cost tiers (relevant to the perf decision): **eager every frame** = registry
  bookkeeping in `widget_finalize` (GetID + GetItemRectMin/Max + IsItemHovered/Active/Focused
  + 3 table inserts + path-key string), runs whether or not anyone snapshots. **lazy on
  snapshot only** = `sprint_json_at` JSON walk (the heavy part). The naive artifact fix
  (materialize per-path payload at finalize) would drag the heavy lazy cost into the eager
  path — which is exactly why we measure first.
- Fix candidates (when we return): (1) gate the eager registry behind an "is live/recording
  active" flag (off in shipping); (2) arm-on-demand snapshot — snapshot arms per-path capture
  for the NEXT frame only (zero steady-state cost, 1-frame-deferred, fits the await infra).
- Confirm it reproduces in a plain dasImgui `for`-loop of `text()` under `with_id` before
  fixing, so the fix is validated in-tree. Matters for Phase 3 (snapshot-driven tests +
  addressing graph state by path) and for "links visible-through-live" (link-as-widget).

## Binding issues (C++ side)

1. **`Config.SettingsFile` is read-only from daslang — FIXED.** The C++ field is
   `const char*`; the generated bind maps it to `string const`, so `cfg.SettingsFile = ""`
   won't compile. imgui-node-editor gates load/save on `if (SettingsFile)`
   (`imgui_node_editor.cpp` ~5760/5806), so nullptr disables `NodeEditor.json` entirely.
   Fix: custom `CreateEditorNoSettings()` added in `src/dasIMGUI_NODE_EDITOR.main.cpp`
   `initMain()` (registered via `addExtern`; forward-declared in `aotRequire`). **`main.cpp`
   is hand-edited and NOT regenerated** by the binder (the `.cpp`/`.inc` files are). If you
   ever regen, only `main.cpp` carries custom code — verify it survived.
2. **`BeginCreate(color,thickness)` / `Link(id,a,b,color,thickness)` need explicit args.**
   The generated bind doesn't surface the C++ default args, so callers must pass
   `float4(1,1,1,1), 1.0`. The v2 boost wrappers should default these when we extract
   `link()` / `on_create()`.

## Known bugs / deferred

- **`NavigateToContent` is DPI-broken.** Under the harness's `GLFW_SCALE_TO_MONITOR` (HiDPI),
  `NavigateToContent(0.0)` computes a view scaled by the monitor content scale (~1.658×) plus
  an off-screen pan, so the canvas only paints its top-left ~1/scale region. Confirmed via
  `editor_dims`: `CanvasToScreen` scale 1.658 = 1/`GetCurrentZoom`(0.603); with navigate
  disabled the view is a clean scale 1.0 at origin (8,8) and the grid fills the window. It is
  **not** HDPI-framebuffer, not glViewport, not the harness `--imgui-content-scale`, not the
  json. The v1 example dodged it by hand-rolling glfw without `SCALE_TO_MONITOR`.
  **Currently disabled in the example.** TODO: fix navigate's DPI handling (likely
  node-editor-side), then re-enable fit-on-startup.
  - **One-shot repro:** the `navigate_to_content` live command flips `g_request_navigate`,
    so the draw loop calls `NavigateToContent(0.0)` on a fully-settled editor. Observed:
    view goes from clean (zoom 1.0, scale 1.0) → **zoom 0.603 / scale 1.658 in a single
    call** (no frame-timing involved). Sharp clue: 0.603 = **1/1.658 exactly** = 1/(monitor
    content scale) — not a fit-to-content number. So navigate applies the content scale
    inversely once (logical-vs-physical canvas-size mismatch in `NavigateTo`/the
    `NavigateAnimation` target view-rect), rather than mis-fitting the graph. Fix lives in
    `imgui_node_editor.cpp` (`NavigateAction::NavigateTo` / canvas `ViewRect`/`CalcViewRect`
    / `GetContentBounds`).

## Debug instrumentation (kept while iterating)

- `editor_dims` live command in `shader_graph.das` → DisplaySize, DisplayFramebufferScale,
  canvas size (`GetScreenSize`), zoom, and `CanvasToScreen` of (0,0)/(1000,1000). Plus
  `g_dbg_*` globals. Keep until the navigate DPI fix is done (wrapper extraction is complete).

## Wrapper roadmap — COMPLETE

All extracted, and since PR #2 as `forward_argument` `[widget]`/`[container]` macros (NOT
hand-unrolled):
- `node(id, (color=…)){}`, `pin(id, kind){}`, `link(id, (from=, to=))` — DONE.
- create: `begin_create` + `query_new_link`/`accept_new_item`/`reject_new_item` — DONE.
- delete: `begin_delete` + PER-KIND `query`/`accept`/`reject` `_link`/`_node` — DONE.
- context menus: `with_suspended` + `show_node/pin/link/background_context_menu` (events) — DONE (PR #4).
- Phase 3 (editor-level JSON snapshot + HTTP live-command graph control) — DONE.

Remaining (see NEXT TASK): write-back/editing, Tier-2 API backlog, optional `add_node` live command.
