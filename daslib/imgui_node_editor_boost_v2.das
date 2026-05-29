options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false
// This module IS the wrapper layer, so it legitimately calls raw
// imgui_node_editor::* — exempt it from its own bundled lint (the lint walks
// getThisModule, so this only matters when boost_v2 is compiled directly).
options _allow_node_editor_native = true

module imgui_node_editor_boost_v2 shared

require imgui public
require imgui_node_editor public
require imgui/imgui_boost_runtime public      // widget_prelude / container_finalize / WidgetEntry
require imgui/imgui_boost_v2 public            // [widget]/[container] forward_argument annotations
require imgui/imgui_node_editor_lint public    // default-on ban on raw imgui_node_editor::* in consumers
require daslib/json
require daslib/json_boost                       // JV for the per-entity payload
require daslib/safe_addr                        // safe_addr(local) -> int? for the create-query bridge

typedef LinkId = int
typedef PinId = int
typedef NodeId = int

// Per-editor "last context menu" telemetry. The show_*_context_menu events record
// the right-clicked target HERE (not in user-land); node_editor_payload surfaces it
// in the snapshot, so the target the app is about to act on stays observable for
// frames to come — independent of whatever the app chooses to render (popup, button,
// nothing). Keyed by intptr(ctx). `kind` is the single source of truth for which
// menu fired last ("" until any fires); each fire REPLACES the whole record, so the
// other targets reset to their invalid (0 / default) values.
struct private CtxMenuState {
    kind : string = ""        //! "" | "node" | "pin" | "link" | "background"
    node : NodeId = 0         //! right-clicked node id when kind=="node" (0 = none)
    pin  : PinId = 0          //! right-clicked pin id when kind=="pin"
    link : LinkId = 0         //! right-clicked link id when kind=="link"
    pos  : float2 = float2(0.0, 0.0)   //! canvas-space click point when kind=="background"
}
var private g_ctx_menus : table<uint64; CtxMenuState>

def private record_ctx_menu(ctx : imgui_node_editor::EditorContext?; var st : CtxMenuState) {
    g_ctx_menus[intptr(ctx)] = st
}

// Last "new node by drag" release per editor — the user dragged from a pin into
// empty canvas and let go. show_new_node_drag records {from_pin, pos} here; it's
// the create-flow peer of CtxMenuState (a drag-release is the same "gesture at a
// point → app spawns" shape as the background context menu, plus a source pin to
// auto-connect). Surfaced in node_editor_payload as last_new_node_drag_*.
struct private NodeDragState {
    from_pin : PinId = 0               //! pin the drag started at (0 = none/never)
    pos      : float2 = float2(0.0, 0.0)   //! canvas-space drop point
}
var private g_node_drags : table<uint64; NodeDragState>

// Last shortcut action per editor — which clipboard/edit shortcut the editor accepted
// this frame (Ctrl+C/X/V/D, etc.). accept_* records it HERE (the events-record-telemetry
// rule, same as CtxMenuState); surfaced in node_editor_payload as last_shortcut_*. Scalar
// (copyable) — the action name + the size of its target set (= the selection the action
// applies to; GetSelectedObjectCount, consistent for real + injected actions). The full
// id lists are read via get_action_context_nodes/links (callable outside the frame).
struct private ShortcutState {
    action       : string = ""   //! "" | "cut" | "copy" | "paste" | "duplicate" | "create_node"
    context_size : int = 0       //! # objects (nodes + links) the action targets
}
var private g_shortcuts : table<uint64; ShortcutState>

// Active editor for the currently-open node_editor() block, set for its duration
// (stored as void? — it only flows into WidgetEntry.serialize_ctx). node/pin/link
// stash it so their lazy snapshot serializers can SetCurrentEditor before querying
// geometry/selection by id.
var private g_active_editor : void? = null

// ===== editor canvas (app-owned context) =====
//
// The EditorContext is the editor's handle and the APP owns it — create N of
// them (one per graph window), pass the ctx to every boost entry point. No
// module singleton. `intptr(ctx)` (uint64) is the stable unique id used to
// target an editor across the live/JSON boundary (see handle_to_editor).

def create_node_editor() : imgui_node_editor::EditorContext? {
    //! Create an editor context with NodeEditor.json persistence disabled (custom
    //! binding — Config.SettingsFile is const in the generated bind). The app owns
    //! the handle: pass it to node_editor()/set_node_position(), free it with
    //! destroy_node_editor(). An app may own several (one per graph). Clipboard/edit
    //! shortcuts (Ctrl+C/X/V/D) are ENABLED by default — consume them via with_shortcuts;
    //! call enable_shortcuts(ctx, false) to opt out.
    var ctx = imgui_node_editor::CreateEditorNoSettings()
    enable_shortcuts(ctx, true)
    return ctx
}

def enable_shortcuts(ctx : imgui_node_editor::EditorContext?; on : bool) : bool {
    //! Toggle whether `ctx` processes clipboard/edit key chords (Ctrl+C/X/V/D, …). On by
    //! default from create_node_editor. Brackets SetCurrentEditor (callable outside the
    //! draw loop). No-op for a null ctx.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::EnableShortcuts(on)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def destroy_node_editor(ctx : imgui_node_editor::EditorContext?) {
    //! Destroy a context from create_node_editor (flushes its settings).
    if (ctx != null) {
        imgui_node_editor::DestroyEditor(ctx)
    }
}

def handle_to_editor(handle : uint64) : imgui_node_editor::EditorContext? {
    //! Resolve a live-command editor handle (= intptr(ctx), exposed in the
    //! node_editor snapshot payload) back to its context. Unsafe by nature: the
    //! handle is a raw pointer value from JSON, so it must originate from a
    //! snapshot of a live editor.
    return unsafe(reinterpret<imgui_node_editor::EditorContext?>(handle))
}

[container(forward_argument=true, verbatim_path=true)]
def node_editor(editor : imgui_node_editor::EditorContext?; size : float2 = float2(0.0, 0.0); blk : block) {
    //! The canvas for ONE graph — `node_editor("name", (editor = ctx, size = float2(0,0))){…}`.
    //! arg0 is the verbatim path key (the canvas name); `editor` is the app-owned
    //! EditorContext. Brackets SetCurrentEditor + Begin/End. Registers as kind
    //! "node_editor" with payload {handle: intptr(editor)} built lazily at snapshot
    //! (node_editor_payload) — `handle` is the unique id the live API targets; no
    //! per-frame JSON. `widget_ident` (= the name) is macro-injected;
    //! child nodes/pins/links nest under it. (Macro injects widget_prelude +
    //! container_path_push/pop.)
    imgui_node_editor::SetCurrentEditor(editor)
    g_active_editor = unsafe(reinterpret<void?>(editor))
    imgui_node_editor::Begin(widget_ident, size)
    invoke(blk)
    imgui_node_editor::End()
    g_active_editor = null
    imgui_node_editor::SetCurrentEditor(null)
    var entry : WidgetEntry
    entry.serialize_ctx = unsafe(reinterpret<void?>(editor))
    entry.serialize = @@node_editor_payload
    finalize_entity(widget_ident, "node_editor", entry)
}

def set_node_position(ctx : imgui_node_editor::EditorContext?; id : NodeId; pos : float2) : bool {
    //! Move a node from OUTSIDE the draw loop (e.g. a live command). The editor
    //! owns node geometry, so this is just SetNodePosition — no app-side position.
    //! Brackets SetCurrentEditor since the context isn't current between frames.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::SetNodePosition(id, pos)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def flow(ctx : imgui_node_editor::EditorContext?; link_id : LinkId;
         dir : imgui_node_editor::FlowDirection = imgui_node_editor::FlowDirection.Forward) : bool {
    //! Trigger a one-shot "data flow" pulse along link_id — a marker that travels the
    //! link and fades over style.FlowDuration. Imperative editor action (NOT a link
    //! property): re-call to re-pulse, or call every frame for continuous flow. Brackets
    //! SetCurrentEditor so it works from outside the draw loop (live command, post-block).
    //! No-op for a null ctx; a stale/deleted link_id is a safe no-op (editor FindLink-guards).
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::Flow(link_id, dir)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

// ===== node ops + view navigation (transient; bracket SetCurrentEditor) =====
//
// Imperative editor actions with no observable state after they run (like flow) —
// they move the viewport or a node's z-order, not graph topology. All bracket
// SetCurrentEditor so they work from outside the draw loop (toolbar button, live
// command). NavigateToContent stays a raw allow-listed call (the app owns the
// SCALE_TO_MONITOR/DPI workaround — see shader_graph.das).

def center_node_on_screen(ctx : imgui_node_editor::EditorContext?; id : NodeId) : bool {
    //! Pan the viewport so `id` is centered. Transient view action (no zoom change);
    //! no-op for a null ctx. (May share NavigateToContent's DPI quirk under
    //! SCALE_TO_MONITOR — call inside the draw loop if the bracketed form mis-centers.)
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::CenterNodeOnScreen(id)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def navigate_to_selection(ctx : imgui_node_editor::EditorContext?; zoom_in : bool = false;
                          duration : float = -1.0) : bool {
    //! Pan/zoom the viewport to frame the current selection over `duration` seconds
    //! (negative = editor default). `zoom_in` also zooms to fit; no-op for a null ctx
    //! (or empty selection — the editor no-ops internally).
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::NavigateToSelection(zoom_in, duration)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def restore_node_state(ctx : imgui_node_editor::EditorContext?; id : NodeId) : bool {
    //! Re-apply `id`'s saved state (position/size) from the editor's settings — undoes
    //! an un-committed move. No-op for a null ctx.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::RestoreNodeState(id)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def set_node_z_position(ctx : imgui_node_editor::EditorContext?; id : NodeId; z : float) : bool {
    //! Set `id`'s draw order (higher = on top). Observable: the z folds into node()'s
    //! snapshot payload (node_payload). No-op for a null ctx.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::SetNodeZPosition(id, z)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

def set_group_size(ctx : imgui_node_editor::EditorContext?; id : NodeId; size : float2) : bool {
    //! Resize the group node `id` from outside the draw loop. The editor owns group
    //! geometry after creation, so this is the group peer of set_node_position. The
    //! result is observable via the group's snapshot bbox. No-op for a null ctx.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::SetGroupSize(id, size)
    imgui_node_editor::SetCurrentEditor(null)
    return true
}

// ===== graph entities (node / pin / link) — id-keyed via forward_argument =====
//
// Each takes the editor's int id as the first arg, forwarded through the
// [widget]/[container] macros' `forward_argument` mode: the macro injects
// widget_prelude + (for containers) container_path_push/pop and a runtime path
// key "{kind}_{id}". The editor owns the entity (no app-side state struct), so
// rather than build a JsonValue per frame the body sets a lazy `serialize` hook
// on the entry (editor handle + id); the payload is reconstructed only when a
// snapshot is requested (widget_entry_jv), by querying the editor. node/pin are
// containers (children nest under them); link is a leaf.

def private finalize_entity(widget_ident : string; kind : string; var entry : WidgetEntry) {
    //! Container finalize for a per-frame entry with a pre-built payload — null
    //! (addr, ti) so the snapshot uses entry.payload verbatim. Keys off the
    //! container chain (self already pushed by the macro prelude).
    container_finalize(widget_ident, kind, entry, null, null)
}

def private finalize_entity_leaf(widget_ident : string; kind : string; var entry : WidgetEntry) {
    //! Leaf (childless) finalize — widget_finalize keys off widget_path_key
    //! (container chain + ident), so a leaf needs no self-push. (container_finalize
    //! would key off the bare chain and collide with the parent's entry.)
    widget_finalize(widget_ident, kind, entry, null, null)
}

// Lazy payload serializers (no-capture). Invoked only at snapshot time via the
// WidgetEntry.serialize hook, never per frame. They re-derive everything from
// (editor handle, id) — the editor is the source of truth for geometry,
// selection and link topology, so nothing is stored per frame. Each brackets
// SetCurrentEditor since the context isn't current outside the node_editor block
// (same pattern as set_node_position).
def private node_editor_payload(ctx : void?; id : int) : JsonValue? {
    // The canvas exposes the app-owned editor handle (= intptr(editor)) the live API
    // targets, plus the last context-menu target (recorded by show_*_context_menu) so
    // it's observable across frames. No editor query needed — both are module state.
    let h = intptr(ctx)
    var cm = CtxMenuState()
    if (key_exists(g_ctx_menus, h)) {
        cm = g_ctx_menus[h]
    }
    var nd = NodeDragState()
    if (key_exists(g_node_drags, h)) {
        nd = g_node_drags[h]
    }
    var sc = ShortcutState()
    if (key_exists(g_shortcuts, h)) {
        sc = g_shortcuts[h]
    }
    return JV((
        handle = h,
        last_context_kind = cm.kind,
        last_node_context_menu = cm.node,
        last_pin_context_menu = cm.pin,
        last_link_context_menu = cm.link,
        last_background_context_menu = cm.pos,
        last_new_node_drag_from_pin = nd.from_pin,
        last_new_node_drag_pos = nd.pos,
        last_shortcut_action = sc.action,
        last_shortcut_context_size = sc.context_size
    ))
}

def private node_payload(ctx : void?; id : int) : JsonValue? {
    let ed = unsafe(reinterpret<imgui_node_editor::EditorContext?>(ctx))
    imgui_node_editor::SetCurrentEditor(ed)
    let pos = imgui_node_editor::GetNodePosition(id)
    let sz = imgui_node_editor::GetNodeSize(id)
    let sel = imgui_node_editor::IsNodeSelected(id)
    let z = imgui_node_editor::GetNodeZPosition(id)
    imgui_node_editor::SetCurrentEditor(null)
    return JV((id = id, bbox = float4(pos.x, pos.y, pos.x + sz.x, pos.y + sz.y), selected = sel, z = z))
}

def private pin_payload(ctx : void?; id : int) : JsonValue? {
    // No editor-queryable pin detail (no GetPinKind), so the payload is just the id.
    return JV((id = id))
}

def private link_payload(ctx : void?; id : int) : JsonValue? {
    let ed = unsafe(reinterpret<imgui_node_editor::EditorContext?>(ctx))
    imgui_node_editor::SetCurrentEditor(ed)
    var from_pin : PinId
    var to_pin : PinId
    imgui_node_editor::GetLinkPins(id, safe_addr(from_pin), safe_addr(to_pin))
    let sel = imgui_node_editor::IsLinkSelected(id)
    imgui_node_editor::SetCurrentEditor(null)
    return JV((id = id, from_pin = from_pin, to_pin = to_pin, selected = sel))
}

[container(forward_argument=true)]
def node(id : NodeId; color : float4 = float4(-1.0, -1.0, -1.0, -1.0); blk : block) {
    //! A graph node — `node(id, (color = …)){…}`. `id` is the editor's node handle.
    //! `color` tints the node body via PushStyleColor(StyleColor.NodeBg); pass a
    //! negative color (e.g. float4(-1,-1,-1,-1)) to keep the editor default.
    //! Registers as kind "node"; payload {id, bbox, selected} is built lazily at
    //! snapshot (node_payload) by querying the editor — the editor owns node
    //! geometry, not ImGui's item rect. entry.bbox is still set per frame for
    //! click-targeting. Child pins/text nest under this node's path. `widget_ident`
    //! is macro-injected (= "node_{id}").
    let tinted = color.x >= 0.0
    if (tinted) {
        imgui_node_editor::PushStyleColor(StyleColor.NodeBg, color)
    }
    imgui_node_editor::BeginNode(id)
    invoke(blk)
    imgui_node_editor::EndNode()
    if (tinted) {
        imgui_node_editor::PopStyleColor(1)
    }
    var entry : WidgetEntry
    let pos = imgui_node_editor::GetNodePosition(id)
    let sz = imgui_node_editor::GetNodeSize(id)
    entry.bbox = float4(pos.x, pos.y, pos.x + sz.x, pos.y + sz.y)
    entry.serialize_id = id
    entry.serialize_ctx = g_active_editor
    entry.serialize = @@node_payload
    finalize_entity(widget_ident, "node", entry)
}

[container(forward_argument=true)]
def node_group(id : NodeId; size : float2 = float2(200.0, 150.0); blk : block) {
    //! A group / comment node — `node_group(id, (size = float2(w,h))){…}`. A group IS a
    //! node: the body renders FIRST (its title becomes the header), then Group(size) lays
    //! the resizable box below it, so child nodes dragged onto it move with it. `size` is a
    //! ONE-TIME seed (like node position) — once the node is a group the editor owns its
    //! bounds and ignores the passed size on later frames; use set_group_size to resize.
    //! Named node_group (not group) to avoid colliding with imgui's BeginGroup/EndGroup
    //! `group` container. Registers as kind "node_group"; payload {id, bbox, selected, z}
    //! is built lazily via node_payload (a group is geometrically a node). `widget_ident`
    //! is macro-injected (= "node_group_{id}").
    imgui_node_editor::BeginNode(id)
    invoke(blk)
    imgui_node_editor::Group(size)
    imgui_node_editor::EndNode()
    var entry : WidgetEntry
    let pos = imgui_node_editor::GetNodePosition(id)
    let sz = imgui_node_editor::GetNodeSize(id)
    entry.bbox = float4(pos.x, pos.y, pos.x + sz.x, pos.y + sz.y)
    entry.serialize_id = id
    entry.serialize_ctx = g_active_editor
    entry.serialize = @@node_payload
    finalize_entity(widget_ident, "node_group", entry)
}

[container(forward_argument=true)]
def pin(id : PinId; kind : PinKind;
        pivot_alignment : float2 = float2(-1.0, -1.0);
        pivot_size : float2 = float2(-1.0, -1.0);
        pivot_scale : float2 = float2(-1.0, -1.0); blk : block) {
    //! A node pin — `pin(id, kind){…}`, or with geometry config via the tuple form
    //! `pin(id, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5)))`. `kind`
    //! drives BeginPin. pivot_alignment (0..1 within the pin rect), pivot_size and
    //! pivot_scale place + size the link-attach point — e.g. align an output pin's pivot
    //! to its right edge so links leave the node cleanly; a negative x (the -1 default on
    //! each) keeps the editor default for that axis. Registers as kind "pin"; payload {id}
    //! is built lazily (pin_payload). `widget_ident` is macro-injected (= "pin_{id}").
    imgui_node_editor::BeginPin(id, kind)
    if (pivot_alignment.x >= 0.0) {
        imgui_node_editor::PinPivotAlignment(pivot_alignment)
    }
    if (pivot_size.x >= 0.0) {
        imgui_node_editor::PinPivotSize(pivot_size)
    }
    if (pivot_scale.x >= 0.0) {
        imgui_node_editor::PinPivotScale(pivot_scale)
    }
    invoke(blk)
    imgui_node_editor::EndPin()
    var entry : WidgetEntry
    entry.serialize_id = id
    entry.serialize = @@pin_payload
    finalize_entity(widget_ident, "pin", entry)
}

[widget(forward_argument=true)]
def link(id : LinkId; from : PinId; to : PinId;
         color : float4 = float4(1.0, 1.0, 1.0, 1.0); thickness : float = 1.0) {
    //! A graph edge — `link(id, (from=…, to=…))`. Leaf (no body); the editor draws
    //! the curve. Registers as kind "link"; payload {id, from_pin, to_pin, selected}
    //! is built lazily at snapshot (link_payload) via GetLinkPins/IsLinkSelected.
    //! Color/thickness defaulted (the generated bind doesn't surface the C++
    //! defaults) and overridable via the tuple. `widget_ident` is macro-injected
    //! (= "link_{id}").
    imgui_node_editor::Link(id, from, to, color, thickness)
    var entry : WidgetEntry
    entry.serialize_id = id
    entry.serialize_ctx = g_active_editor
    entry.serialize = @@link_payload
    finalize_entity_leaf(widget_ident, "link", entry)
}

// ===== rendering config (style-var stack + custom node background) =====

def with_style_var(style_var : imgui_node_editor::StyleVar; value : float; blk : block) {
    //! Bracket PushStyleVar/PopStyleVar(1) around the body for a node-editor style var
    //! (e.g. StyleVar.NodeRounding, StyleVar.NodeBorderWidth). Overloaded for float /
    //! float2 / float4 values. Pure rendering config — no snapshot state.
    imgui_node_editor::PushStyleVar(style_var, value)
    invoke(blk)
    imgui_node_editor::PopStyleVar(1)
}

def with_style_var(style_var : imgui_node_editor::StyleVar; value : float2; blk : block) {
    imgui_node_editor::PushStyleVar(style_var, value)
    invoke(blk)
    imgui_node_editor::PopStyleVar(1)
}

def with_style_var(style_var : imgui_node_editor::StyleVar; value : float4; blk : block) {
    imgui_node_editor::PushStyleVar(style_var, value)
    invoke(blk)
    imgui_node_editor::PopStyleVar(1)
}

def with_style_color(style_color : imgui_node_editor::StyleColor; color : float4; blk : block) {
    //! Bracket PushStyleColor/PopStyleColor(1) around the body for a node-editor style
    //! color (e.g. StyleColor.NodeBorder, StyleColor.HovNodeBorder, StyleColor.Flow) —
    //! the color peer of with_style_var. Scopes a per-node/per-region override on top of
    //! the editor's ed::Style (see imgui_node_editor_theme_daslang). node()'s `color` arg
    //! already covers NodeBg; reach for this for the other slots. Pure rendering config —
    //! no snapshot state.
    imgui_node_editor::PushStyleColor(style_color, color)
    invoke(blk)
    imgui_node_editor::PopStyleColor(1)
}

def group_hint(id : NodeId; blk : block<(var fg : ImDrawList?; var bg : ImDrawList?) : void>) : bool {
    //! Draw an off-screen group-label overlay for group node `id`. The editor only renders
    //! hints when the canvas is zoomed out (view scale <= 0.75) AND `id` is a group, so
    //! this returns false (block NOT invoked) otherwise — call it unconditionally per
    //! group each frame and it self-gates. The block receives the hint foreground +
    //! background draw lists (feed them add_text / add_rect_filled); position art via
    //! GetGroupMin()/GetGroupMax(). Must run INSIDE the node_editor() block and NOT inside
    //! with_suspended (BeginGroupHint suspends/resumes the editor internally). Decorative —
    //! no snapshot state.
    return false if (!imgui_node_editor::BeginGroupHint(id))
    var fg = imgui_node_editor::GetHintForegroundDrawList()
    var bg = imgui_node_editor::GetHintBackgroundDrawList()
    invoke(blk, fg, bg)
    imgui_node_editor::EndGroupHint()
    return true
}

def with_node_background_drawlist(id : NodeId; blk : block<(var dl : ImDrawList?) : void>) {
    //! Hand the body node `id`'s background draw list to paint custom art BEHIND the node
    //! (mirrors dasImgui's with_*_drawlist). Feed `dl` to the imgui drawlist primitives
    //! (add_rect_filled, add_line, …). Call it AFTER the node()/group() block (the node
    //! must be fully built — its draw channels only exist post-EndNode; calling mid-body
    //! crashes), still inside the node_editor() block. Decorative — no snapshot state.
    var dl = imgui_node_editor::GetNodeBackgroundDrawList(id)
    invoke(blk, dl)
}

// ===== link creation (queue-injectable; drivable via live) =====
//
// begin_create / query_new_link / accept_new_item mirror imgui-node-editor's
// BeginCreate/QueryNewLink/AcceptNewItem, but each also serves a link queued by
// enqueue_new_link: the next frame replays the queued link through the SAME app
// create handler the mouse drives, so topology stays app-owned and bidirectional.
// has_pending(h) holds across begin->query->accept within a frame (we pop only on
// accept), so the three wrappers just test it; a queued link wins over a live drag.

struct private PendingLink {
    editor : uint64
    from   : PinId
    to     : PinId
}

var private g_pending_links : array<PendingLink>

def private has_pending(h : uint64) : bool {
    for (pl in g_pending_links) {
        return true if (pl.editor == h)
    }
    return false
}

def private front_pending(h : uint64) : PendingLink {
    for (pl in g_pending_links) {
        return pl if (pl.editor == h)
    }
    return PendingLink()
}

def private pop_pending(h : uint64) {
    for (i in range(length(g_pending_links))) {
        if (g_pending_links[i].editor == h) {
            g_pending_links |> erase(i)
            return
        }
    }
}

def enqueue_new_link(ctx : imgui_node_editor::EditorContext?; from : PinId; to : PinId) : bool {
    //! Queue a link (from_pin -> to_pin) to be created in `ctx` on its next frame.
    //! The create wrappers replay it through the app's own create handler, so the
    //! app writes its graph exactly as for a mouse-dragged link. Returns false for
    //! a null ctx or a 0 pin id (0 is the editor's "no pin" sentinel).
    return false if (ctx == null || from == 0 || to == 0)
    g_pending_links |> push(PendingLink(editor = intptr(ctx), from = from, to = to))
    return true
}

def clear_pending_links(ctx : imgui_node_editor::EditorContext?) {
    //! Drop all queued (not-yet-created) links for `ctx`. The queue pops only on
    //! accept_new_item, so a link the app's create handler refuses would otherwise be
    //! re-offered every frame — call this to cancel such stuck injections.
    return if (ctx == null)
    let h = intptr(ctx)
    g_pending_links |> erase_if() $(pl) {
        return pl.editor == h
    }
}

// Queued "new node by drag" releases (the enqueue_new_node_drag injection rail —
// the testable/drivable twin of a real pin-drag-into-empty-space). Pop-on-serve,
// one-shot: a drag-release is a single moment, not a multi-frame offer like a link.
struct private PendingNodeDrag {
    editor   : uint64
    from_pin : PinId
    pos      : float2
}

var private g_pending_node_drags : array<PendingNodeDrag>

def private has_pending_node_drag(h : uint64) : bool {
    for (pd in g_pending_node_drags) {
        return true if (pd.editor == h)
    }
    return false
}

def enqueue_new_node_drag(ctx : imgui_node_editor::EditorContext?; from_pin : PinId; pos : float2) : bool {
    //! Queue a synthetic "new node by drag" release for `ctx` — the source pin the
    //! drag began at + the canvas-space drop point. show_new_node_drag serves it on
    //! the next frame exactly as a real release, firing the app's create-node flow.
    //! The drivable/testable twin of dragging from a pin into empty canvas (pin
    //! geometry isn't queryable, so a real drag can't be synth-targeted). Returns
    //! false for a null ctx or 0 source pin.
    return false if (ctx == null || from_pin == 0)
    g_pending_node_drags |> push(PendingNodeDrag(editor = intptr(ctx), from_pin = from_pin, pos = pos))
    return true
}

def begin_create(ctx : imgui_node_editor::EditorContext?; blk : block) {
    //! Bracket BeginCreate/EndCreate for `ctx` (drag-preview link drawn white, 1px).
    //! Invokes the body when the user is dragging a new link/node OR a queued link
    //! or node-drag is pending. Inside, call query_new_link + accept_new_item and/or
    //! show_new_node_drag — they transparently serve the queued item when injecting.
    let native = imgui_node_editor::BeginCreate(float4(1.0, 1.0, 1.0, 1.0), 1.0)
    let h = intptr(ctx)
    if (native || has_pending(h) || has_pending_node_drag(h)) {
        invoke(blk)
    }
    imgui_node_editor::EndCreate()
}

def query_new_link(ctx : imgui_node_editor::EditorContext?; var from_pin : PinId&; var to_pin : PinId&) : bool {
    //! Inside begin_create: report the pins of the link being created (out-params by
    //! reference). Returns the queued link's pins when injecting, else the live drag's.
    let h = intptr(ctx)
    if (has_pending(h)) {
        let pl = front_pending(h)
        from_pin = pl.from
        to_pin = pl.to
        return true
    }
    var a = 0
    var b = 0
    let ok = imgui_node_editor::QueryNewLink(safe_addr(a), safe_addr(b))
    from_pin = a
    to_pin = b
    return ok
}

def accept_new_item(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside begin_create, after query_new_link: accept the new link. Pops the
    //! queued link (created once) when injecting, else defers to the editor (which
    //! returns true only on the commit frame of a live drag).
    let h = intptr(ctx)
    if (has_pending(h)) {
        pop_pending(h)
        return true
    }
    return imgui_node_editor::AcceptNewItem()
}

def reject_new_item(ctx : imgui_node_editor::EditorContext?) {
    //! Inside begin_create, after query_new_link: refuse the link. Pops the queued
    //! link (consumes the decision) when injecting; for a live drag calls the editor's
    //! RejectNewItem so it draws the red "won't connect" preview. Call accept OR reject
    //! once the app has decided — calling NEITHER keeps the (queued) offer alive across
    //! frames, which is how an app can show an indication for a few frames before deciding.
    let h = intptr(ctx)
    if (has_pending(h)) {
        pop_pending(h)
        return
    }
    imgui_node_editor::RejectNewItem()
}

def show_new_node_drag(ctx : imgui_node_editor::EditorContext?; var from_pin : PinId&; var drop_pos : float2&) : bool {
    //! Inside begin_create: true the frame the user drops a pin-drag in empty canvas
    //! (or a queued drag is served). Hands back the source pin + canvas-space drop
    //! point and records last_new_node_drag on the editor. The app responds by opening
    //! its create-node UI and, on pick, spawning at drop_pos + enqueue_new_link(source
    //! -> new pin). Returns false (no out-param write) otherwise. EVENT, not a scope —
    //! folds QueryNewNode + AcceptNewItem (green "can drop" preview during the drag).
    let h = intptr(ctx)
    // Injected drag wins (pop-on-serve, one-shot) — bypasses the editor interaction,
    // same as enqueue_new_link vs a live drag.
    for (i in range(length(g_pending_node_drags))) {
        if (g_pending_node_drags[i].editor == h) {
            let pd = g_pending_node_drags[i]
            from_pin = pd.from_pin
            drop_pos = pd.pos
            g_pending_node_drags |> erase(i)
            g_node_drags[h] = NodeDragState(from_pin = pd.from_pin, pos = pd.pos)
            return true
        }
    }
    // Live drag: QueryNewNode is true while dragging into empty space (hands back the
    // source pin); AcceptNewItem arms the green preview and returns true on release.
    var p = 0
    if (imgui_node_editor::QueryNewNode(safe_addr(p))) {
        if (imgui_node_editor::AcceptNewItem()) {
            from_pin = p
            drop_pos = imgui_node_editor::ScreenToCanvas(GetMousePos())
            g_node_drags[h] = NodeDragState(from_pin = p, pos = drop_pos)
            return true
        }
    }
    return false
}

// ===== item deletion (queue-injectable; drivable via live) =====
//
// Links and nodes are FULLY DECOUPLED — each has its own queue, its own servicing
// flag, and its own query/accept/reject wrapper. Same pop-on-DECISION shape as
// create: query PEEKS the front of its kind's queue; accept/reject POP it (accept
// also applies the deletion, reject just drops the request). The per-kind flag tells
// accept/reject whether the current item is queued (pop our queue) or native (defer
// to the editor), and lets query auto-drop a still-undecided prior item so the
// while-loop always advances — mirroring imgui-node-editor's own auto-reject-on-
// next-query (imgui_node_editor.cpp QueryItem).

struct private PendingDelete {
    editor : uint64
    id     : int
}

var private g_link_deletes : array<PendingDelete>
var private g_node_deletes : array<PendingDelete>
var private g_link_delete_servicing : bool = false   // current query_deleted_link handed out a queued link
var private g_node_delete_servicing : bool = false   // current query_deleted_node handed out a queued node

def private dq_has(arr : array<PendingDelete>; h : uint64) : bool {
    for (pd in arr) {
        return true if (pd.editor == h)
    }
    return false
}

def private dq_peek(arr : array<PendingDelete>; h : uint64; var out_id : int&) : bool {
    for (pd in arr) {
        if (pd.editor == h) {
            out_id = pd.id
            return true
        }
    }
    return false
}

def private dq_pop(var arr : array<PendingDelete>; h : uint64) {
    for (i in range(length(arr))) {
        if (arr[i].editor == h) {
            arr |> erase(i)
            return
        }
    }
}

def enqueue_delete_node(ctx : imgui_node_editor::EditorContext?; id : NodeId) : bool {
    //! Queue a node deletion to be replayed through `ctx`'s delete handler next frame
    //! (same path as a Delete-key press). Returns false for a null ctx or 0 id.
    return false if (ctx == null || id == 0)
    g_node_deletes |> push(PendingDelete(editor = intptr(ctx), id = id))
    return true
}

def enqueue_delete_link(ctx : imgui_node_editor::EditorContext?; id : LinkId) : bool {
    //! Queue a link deletion to be replayed through `ctx`'s delete handler next frame.
    //! Returns false for a null ctx or 0 id.
    return false if (ctx == null || id == 0)
    g_link_deletes |> push(PendingDelete(editor = intptr(ctx), id = id))
    return true
}

def clear_pending_deletes(ctx : imgui_node_editor::EditorContext?) {
    //! Drop all queued (not-yet-applied) link AND node deletions for `ctx`. Bulk flush.
    return if (ctx == null)
    let h = intptr(ctx)
    g_link_deletes |> erase_if() $(pd) {
        return pd.editor == h
    }
    g_node_deletes |> erase_if() $(pd) {
        return pd.editor == h
    }
}

def begin_delete(ctx : imgui_node_editor::EditorContext?; blk : block) {
    //! Bracket BeginDelete/EndDelete for `ctx`. Invokes the body when the user pressed
    //! Delete on a selection OR a queued link/node deletion is pending. Inside, drain
    //! with the query_deleted_link / query_deleted_node while-loops.
    let native = imgui_node_editor::BeginDelete()
    let h = intptr(ctx)
    if (native || dq_has(g_link_deletes, h) || dq_has(g_node_deletes, h)) {
        invoke(blk)
    }
    imgui_node_editor::EndDelete()
}

def query_deleted_link(ctx : imgui_node_editor::EditorContext?; var lid : LinkId&) : bool {
    //! Inside begin_delete: report the next link being deleted (out-param by reference).
    //! PEEKS the front queued link delete (accept/reject pop it); auto-drops a prior
    //! undecided one so the loop advances, then falls through to native QueryDeletedLink.
    let h = intptr(ctx)
    if (g_link_delete_servicing) {
        dq_pop(g_link_deletes, h)            // prior item left undecided → drop it (auto-reject)
        g_link_delete_servicing = false
    }
    var id = 0
    if (dq_peek(g_link_deletes, h, id)) {
        lid = id
        g_link_delete_servicing = true
        return true
    }
    var x = 0
    let ok = imgui_node_editor::QueryDeletedLink(safe_addr(x), null, null)
    lid = x
    return ok
}

def query_deleted_node(ctx : imgui_node_editor::EditorContext?; var nid : NodeId&) : bool {
    //! Inside begin_delete: report the next node being deleted. PEEKS the front queued
    //! node delete; auto-drops a prior undecided one, then native QueryDeletedNode.
    let h = intptr(ctx)
    if (g_node_delete_servicing) {
        dq_pop(g_node_deletes, h)
        g_node_delete_servicing = false
    }
    var id = 0
    if (dq_peek(g_node_deletes, h, id)) {
        nid = id
        g_node_delete_servicing = true
        return true
    }
    var x = 0
    let ok = imgui_node_editor::QueryDeletedNode(safe_addr(x))
    nid = x
    return ok
}

def accept_deleted_link(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside begin_delete, after query_deleted_link: accept the deletion (true => app
    //! removes the link). Pops the queued link when injecting, else AcceptDeletedItem.
    if (g_link_delete_servicing) {
        dq_pop(g_link_deletes, intptr(ctx))
        g_link_delete_servicing = false
        return true
    }
    return imgui_node_editor::AcceptDeletedItem(true)
}

def reject_deleted_link(ctx : imgui_node_editor::EditorContext?) {
    //! Inside begin_delete, after query_deleted_link: refuse the deletion (app keeps the
    //! link). Pops the queued link (drops the request) when injecting, else RejectDeletedItem.
    if (g_link_delete_servicing) {
        dq_pop(g_link_deletes, intptr(ctx))
        g_link_delete_servicing = false
        return
    }
    imgui_node_editor::RejectDeletedItem()
}

def accept_deleted_node(ctx : imgui_node_editor::EditorContext?; delete_dependencies : bool = true) : bool {
    //! Inside begin_delete, after query_deleted_node: accept the deletion (true => app
    //! removes the node). Pops the queued node when injecting, else AcceptDeletedItem.
    if (g_node_delete_servicing) {
        dq_pop(g_node_deletes, intptr(ctx))
        g_node_delete_servicing = false
        return true
    }
    return imgui_node_editor::AcceptDeletedItem(delete_dependencies)
}

def reject_deleted_node(ctx : imgui_node_editor::EditorContext?) {
    //! Inside begin_delete, after query_deleted_node: refuse the deletion (app keeps the
    //! node). Pops the queued node (drops the request) when injecting, else RejectDeletedItem.
    if (g_node_delete_servicing) {
        dq_pop(g_node_deletes, intptr(ctx))
        g_node_delete_servicing = false
        return
    }
    imgui_node_editor::RejectDeletedItem()
}

// ===== selection (per-editor; bracket SetCurrentEditor for use outside the draw loop) =====

def get_selected_nodes(ctx : imgui_node_editor::EditorContext?) : array<NodeId> {
    //! Currently-selected node ids in `ctx`. Safe to call from a toolbar button or
    //! live command (brackets SetCurrentEditor since the context isn't current
    //! between frames). The buffer is pointer-sized slots — node ids are written
    //! as pointer-sized values and read back via intptr.
    var result : array<NodeId>
    return <- result if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    let count = imgui_node_editor::GetSelectedObjectCount()
    if (count > 0) {
        var buf : array<void?>
        buf |> resize(count)
        var n = 0
        unsafe {
            n = imgui_node_editor::GetSelectedNodes(reinterpret<NodeId?>(addr(buf[0])), count)
        }
        result <- [for (i in range(n)); NodeId(intptr(buf[i]))]
        delete buf
    }
    imgui_node_editor::SetCurrentEditor(null)
    return <- result
}

def get_selected_links(ctx : imgui_node_editor::EditorContext?) : array<LinkId> {
    //! Currently-selected link ids in `ctx`. Same bracketing as get_selected_nodes.
    var result : array<LinkId>
    return <- result if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    let count = imgui_node_editor::GetSelectedObjectCount()
    if (count > 0) {
        var buf : array<void?>
        buf |> resize(count)
        var n = 0
        unsafe {
            n = imgui_node_editor::GetSelectedLinks(reinterpret<LinkId?>(addr(buf[0])), count)
        }
        result <- [for (i in range(n)); LinkId(intptr(buf[i]))]
        delete buf
    }
    imgui_node_editor::SetCurrentEditor(null)
    return <- result
}

def get_ordered_node_ids(ctx : imgui_node_editor::EditorContext?) : array<NodeId> {
    //! All node ids in the editor's current draw order (back-to-front). Pure read; same
    //! bracketing + out-buffer pattern as get_selected_nodes (capacity = GetNodeCount).
    //! Walk it top-down for hit-testing, or persist it to restore z-order.
    var result : array<NodeId>
    return <- result if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    let count = imgui_node_editor::GetNodeCount()
    if (count > 0) {
        var buf : array<void?>
        buf |> resize(count)
        var n = 0
        unsafe {
            n = imgui_node_editor::GetOrderedNodeIds(reinterpret<NodeId?>(addr(buf[0])), count)
        }
        result <- [for (i in range(n)); NodeId(intptr(buf[i]))]
        delete buf
    }
    imgui_node_editor::SetCurrentEditor(null)
    return <- result
}

def select_node(ctx : imgui_node_editor::EditorContext?; id : NodeId; on : bool) {
    //! Select (on) or deselect (off) a node in `ctx`. `on` appends to the current
    //! selection (doesn't clear others); use clear_selection first for exclusive.
    return if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    if (on) {
        imgui_node_editor::SelectNode(id, true)
    } else {
        imgui_node_editor::DeselectNode(id)
    }
    imgui_node_editor::SetCurrentEditor(null)
}

def select_link(ctx : imgui_node_editor::EditorContext?; id : LinkId; on : bool) {
    //! Select (on) or deselect (off) a link in `ctx`. Appends like select_node.
    return if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    if (on) {
        imgui_node_editor::SelectLink(id, true)
    } else {
        imgui_node_editor::DeselectLink(id)
    }
    imgui_node_editor::SetCurrentEditor(null)
}

def clear_selection(ctx : imgui_node_editor::EditorContext?) {
    //! Clear all selection in `ctx`.
    return if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::ClearSelection()
    imgui_node_editor::SetCurrentEditor(null)
}

// ===== context menus (right-click; opened + drawn in a Suspend/Resume island) =====
//
// imgui-node-editor renders the canvas in a transformed space, so context-menu
// detection must run inside Suspend()/Resume() (screen space). These are EVENTS,
// not scopes — they fire true on the right-click frame and hand back the target;
// the app decides what (if anything) to render in response (popup, button, …).
// Each fire ALSO records the target on the editor (see CtxMenuState above), so the
// snapshot shows it for frames to come without any app-side plumbing. Pattern:
//   with_suspended() {
//       var id = 0
//       if (show_node_context_menu(ctx, id))       { open_popup("node-menu") }
//       elif (show_background_context_menu(ctx, p)) { open_popup("bg-menu") }
//       popup_window(NODE_MENU, (str_id = "node-menu", …)) { ... }
//   }
// (open_popup / popup_window / menu_label are the standard imgui_boost_v2 wrappers.)

def with_suspended(blk : block) {
    //! Bracket Suspend()/Resume() around the body. Context-menu detection and the
    //! popups it opens must run here (screen space), not under the canvas transform.
    imgui_node_editor::Suspend()
    invoke(blk)
    imgui_node_editor::Resume()
}

def show_background_context_menu(ctx : imgui_node_editor::EditorContext?; var canvas_pos : float2&) : bool {
    //! True the frame the user right-clicks empty canvas; writes the canvas-space
    //! click point into canvas_pos. Records {kind:"background", pos} on the editor.
    //! Call inside with_suspended.
    let ok = imgui_node_editor::ShowBackgroundContextMenu()
    if (ok) {
        canvas_pos = imgui_node_editor::ScreenToCanvas(GetMousePos())
        record_ctx_menu(ctx, CtxMenuState(kind = "background", pos = canvas_pos))
    }
    return ok
}

def show_node_context_menu(ctx : imgui_node_editor::EditorContext?; var nid : NodeId&) : bool {
    //! True (and writes nid) the frame the user right-clicks a node. Records
    //! {kind:"node", node:nid} on the editor. Call inside with_suspended.
    var x = 0
    let ok = imgui_node_editor::ShowNodeContextMenu(safe_addr(x))
    if (ok) {
        nid = x
        record_ctx_menu(ctx, CtxMenuState(kind = "node", node = x))
    }
    return ok
}

def show_pin_context_menu(ctx : imgui_node_editor::EditorContext?; var pid : PinId&) : bool {
    //! True (and writes pid) the frame the user right-clicks a pin. Records
    //! {kind:"pin", pin:pid} on the editor. Call inside with_suspended.
    var x = 0
    let ok = imgui_node_editor::ShowPinContextMenu(safe_addr(x))
    if (ok) {
        pid = x
        record_ctx_menu(ctx, CtxMenuState(kind = "pin", pin = x))
    }
    return ok
}

def show_link_context_menu(ctx : imgui_node_editor::EditorContext?; var lid : LinkId&) : bool {
    //! True (and writes lid) the frame the user right-clicks a link. Records
    //! {kind:"link", link:lid} on the editor. Call inside with_suspended.
    var x = 0
    let ok = imgui_node_editor::ShowLinkContextMenu(safe_addr(x))
    if (ok) {
        lid = x
        record_ctx_menu(ctx, CtxMenuState(kind = "link", link = x))
    }
    return ok
}

// ===== clipboard / edit shortcuts (events; queue-injectable; drivable via live) =====
//
// The editor detects the key chords itself (Ctrl+C/X/V/D, …) when shortcuts are enabled;
// at most one action is current per frame. The contract is a strict scope: only inside a
// true BeginShortcut()/EndShortcut() may the Accept* be called (each ASSERTS m_InAction).
// with_shortcuts brackets that scope; accept_<kind> is the event (true iff that action
// fired), records it on the editor (ShortcutState telemetry), and ALSO serves an injected
// shortcut (enqueue_shortcut) so a live command / test can drive copy/paste deterministically
// without synthesizing keystrokes — the wrapper makes accept_<kind> return true, replaying
// through the SAME app handler the chord drives. The editor owns no clipboard CONTENT: the
// app serializes the target set (get_action_context_nodes/links or its selection) on copy and
// recreates on paste — topology stays app-owned, exactly like deletes.

let private SHORTCUT_KINDS : table<string> <- { "cut", "copy", "paste", "duplicate", "create_node" }

struct private PendingShortcut {
    editor : uint64
    kind   : string
}
var private g_pending_shortcuts : array<PendingShortcut>
var private g_shortcut_native : table<uint64; bool>   // did BeginShortcut() return true this frame?

def private sc_has_pending(h : uint64) : bool {
    for (ps in g_pending_shortcuts) {
        return true if (ps.editor == h)
    }
    return false
}

def private sc_pop_if(h : uint64; kind : string) : bool {
    for (i in range(length(g_pending_shortcuts))) {
        if (g_pending_shortcuts[i].editor == h && g_pending_shortcuts[i].kind == kind) {
            g_pending_shortcuts |> erase(i)
            return true
        }
    }
    return false
}

def private record_shortcut(ctx : imgui_node_editor::EditorContext?; kind : string) {
    // Editor is current here (accept_* runs inside the node_editor block). The action's
    // target set IS the selection (GetActionContextNodes/Links read GetSelectedObjects);
    // GetSelectedObjectCount is the uniform source — GetActionContextSize reads m_Context,
    // which is only populated for a REAL chord (0 under injection).
    g_shortcuts[intptr(ctx)] = ShortcutState(action = kind, context_size = imgui_node_editor::GetSelectedObjectCount())
}

def private sc_take(ctx : imgui_node_editor::EditorContext?; h : uint64; kind : string; native_ok : bool) : bool {
    // Injected wins; native_ok is pre-guarded by the caller (AcceptX() only evaluated when
    // BeginShortcut() was true this frame, so the m_InAction assert can't trip).
    if (sc_pop_if(h, kind) || native_ok) {
        record_shortcut(ctx, kind)
        return true
    }
    return false
}

def with_shortcuts(ctx : imgui_node_editor::EditorContext?; blk : block) {
    //! Bracket BeginShortcut/EndShortcut for `ctx`. Invokes the body when the editor accepted
    //! a clipboard/edit chord this frame OR a shortcut is queued (enqueue_shortcut). Inside,
    //! branch on accept_copy / accept_cut / accept_paste / accept_duplicate / accept_create_node.
    //! Must run INSIDE the node_editor() block (the editor must be current), NOT inside
    //! with_suspended. Shortcuts must be enabled (on by default; see enable_shortcuts).
    let native = imgui_node_editor::BeginShortcut()
    let h = intptr(ctx)
    g_shortcut_native[h] = native
    if (native || sc_has_pending(h)) {
        invoke(blk)
    }
    if (native) {
        imgui_node_editor::EndShortcut()
    }
}

def accept_copy(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside with_shortcuts: true the frame a Copy fired (or a queued "copy" is served).
    //! Records {action:"copy"} on the editor. Respond by serializing the target set
    //! (get_action_context_nodes/links, or the app's selection) into the app's clipboard.
    let h = intptr(ctx)
    return sc_take(ctx, h, "copy", (g_shortcut_native?[h] ?? false) && imgui_node_editor::AcceptCopy())
}

def accept_cut(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside with_shortcuts: true on a Cut. Records {action:"cut"}. Respond by copying the
    //! target set to the clipboard AND deleting it (via the app's delete path).
    let h = intptr(ctx)
    return sc_take(ctx, h, "cut", (g_shortcut_native?[h] ?? false) && imgui_node_editor::AcceptCut())
}

def accept_paste(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside with_shortcuts: true on a Paste. Records {action:"paste"}. Respond by recreating
    //! the app's clipboard contents as new nodes/links.
    let h = intptr(ctx)
    return sc_take(ctx, h, "paste", (g_shortcut_native?[h] ?? false) && imgui_node_editor::AcceptPaste())
}

def accept_duplicate(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside with_shortcuts: true on a Duplicate. Records {action:"duplicate"}. Respond by
    //! cloning the target set in place (a self-contained copy+paste, no clipboard needed).
    let h = intptr(ctx)
    return sc_take(ctx, h, "duplicate", (g_shortcut_native?[h] ?? false) && imgui_node_editor::AcceptDuplicate())
}

def accept_create_node(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Inside with_shortcuts: true on a CreateNode shortcut. Records {action:"create_node"}.
    //! Respond by opening the app's create-node UI.
    let h = intptr(ctx)
    return sc_take(ctx, h, "create_node", (g_shortcut_native?[h] ?? false) && imgui_node_editor::AcceptCreateNode())
}

def enqueue_shortcut(ctx : imgui_node_editor::EditorContext?; kind : string) : bool {
    //! Queue a shortcut to be served on `ctx`'s next frame — `kind` in {"cut","copy","paste",
    //! "duplicate","create_node"}. with_shortcuts replays it through the app's accept_<kind>
    //! handler exactly as a real chord, so copy/paste is drivable/testable without keystrokes.
    //! Returns false for a null ctx or an unknown kind. Queue what your app actually handles —
    //! an unhandled kind lingers (flush with clear_pending_shortcuts).
    return false if (ctx == null || !key_exists(SHORTCUT_KINDS, kind))
    g_pending_shortcuts |> push(PendingShortcut(editor = intptr(ctx), kind = kind))
    return true
}

def clear_pending_shortcuts(ctx : imgui_node_editor::EditorContext?) {
    //! Drop all queued (not-yet-served) shortcuts for `ctx`.
    return if (ctx == null)
    let h = intptr(ctx)
    g_pending_shortcuts |> erase_if() $(ps) {
        return ps.editor == h
    }
}

def get_action_context_nodes(ctx : imgui_node_editor::EditorContext?) : array<NodeId> {
    //! The node ids the current shortcut action applies to (the selected nodes). Safe outside
    //! the draw loop (brackets SetCurrentEditor); same out-buffer pattern as get_selected_nodes.
    var result : array<NodeId>
    return <- result if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    let count = imgui_node_editor::GetSelectedObjectCount()   // capacity: GetActionContextNodes filters the selection
    if (count > 0) {
        var buf : array<void?>
        buf |> resize(count)
        var n = 0
        unsafe {
            n = imgui_node_editor::GetActionContextNodes(reinterpret<NodeId?>(addr(buf[0])), count)
        }
        result <- [for (i in range(n)); NodeId(intptr(buf[i]))]
        delete buf
    }
    imgui_node_editor::SetCurrentEditor(null)
    return <- result
}

def get_action_context_links(ctx : imgui_node_editor::EditorContext?) : array<LinkId> {
    //! The link ids the current shortcut action applies to (the selected links). Same
    //! bracketing + out-buffer pattern as get_action_context_nodes.
    var result : array<LinkId>
    return <- result if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    let count = imgui_node_editor::GetSelectedObjectCount()
    if (count > 0) {
        var buf : array<void?>
        buf |> resize(count)
        var n = 0
        unsafe {
            n = imgui_node_editor::GetActionContextLinks(reinterpret<LinkId?>(addr(buf[0])), count)
        }
        result <- [for (i in range(n)); LinkId(intptr(buf[i]))]
        delete buf
    }
    imgui_node_editor::SetCurrentEditor(null)
    return <- result
}
