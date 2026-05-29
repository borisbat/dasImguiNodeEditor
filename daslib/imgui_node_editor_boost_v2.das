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
    //! destroy_node_editor(). An app may own several (one per graph).
    return imgui_node_editor::CreateEditorNoSettings()
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
    return JV((
        handle = h,
        last_context_kind = cm.kind,
        last_node_context_menu = cm.node,
        last_pin_context_menu = cm.pin,
        last_link_context_menu = cm.link,
        last_background_context_menu = cm.pos
    ))
}

def private node_payload(ctx : void?; id : int) : JsonValue? {
    let ed = unsafe(reinterpret<imgui_node_editor::EditorContext?>(ctx))
    imgui_node_editor::SetCurrentEditor(ed)
    let pos = imgui_node_editor::GetNodePosition(id)
    let sz = imgui_node_editor::GetNodeSize(id)
    let sel = imgui_node_editor::IsNodeSelected(id)
    imgui_node_editor::SetCurrentEditor(null)
    return JV((id = id, bbox = float4(pos.x, pos.y, pos.x + sz.x, pos.y + sz.y), selected = sel))
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
def pin(id : PinId; kind : PinKind; blk : block) {
    //! A node pin — `pin(id, kind){…}`. Registers as kind "pin"; payload {id} is
    //! built lazily at snapshot (pin_payload). `kind` drives BeginPin but isn't
    //! editor-queryable, so it's not in the payload. `widget_ident` is macro-injected
    //! (= "pin_{id}").
    imgui_node_editor::BeginPin(id, kind)
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

def begin_create(ctx : imgui_node_editor::EditorContext?; blk : block) {
    //! Bracket BeginCreate/EndCreate for `ctx` (drag-preview link drawn white, 1px).
    //! Invokes the body when the user is dragging a new link OR a queued link is
    //! pending. Inside, call query_new_link + accept_new_item — they transparently
    //! serve the queued link when injecting.
    let native = imgui_node_editor::BeginCreate(float4(1.0, 1.0, 1.0, 1.0), 1.0)
    let h = intptr(ctx)
    if (native || has_pending(h)) {
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
