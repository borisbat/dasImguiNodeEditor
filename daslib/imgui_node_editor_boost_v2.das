options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

module imgui_node_editor_boost_v2 shared

require imgui public
require imgui_node_editor public
require imgui/imgui_boost_runtime public      // widget_prelude / container_finalize / WidgetEntry
require daslib/json
require daslib/json_boost                       // JV for the per-entity payload
require daslib/safe_addr                        // safe_addr(local) -> int? for the create-query bridge

typedef LinkId = int
typedef PinId = int
typedef NodeId = int

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

def node_editor(ctx : imgui_node_editor::EditorContext?; name : string; blk : block) {
    //! The canvas for ONE graph. `ctx` is the app-owned EditorContext. Brackets
    //! SetCurrentEditor(ctx) + Begin/End. Registers as kind "node_editor" with
    //! payload {handle: intptr(ctx), name} — `handle` is the unique id the live
    //! API targets. Child nodes/pins/links nest under this editor's path (`name`).
    widget_prelude(name)
    container_path_push(name)
    imgui_node_editor::SetCurrentEditor(ctx)
    imgui_node_editor::Begin(name, float2(0.0, 0.0))
    invoke(blk)
    imgui_node_editor::End()
    imgui_node_editor::SetCurrentEditor(null)
    var entry : WidgetEntry
    entry.payload = JV((handle = intptr(ctx), name = name))
    finalize_entity(name, "node_editor", entry)
    container_path_pop()
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

// ===== graph entities (node / pin / link) — id-only, hand-unrolled =====
//
// Each takes ONLY an id — the editor's node/pin/link handle (internally a
// pointer on the C++ side), so there's no bound struct and no app-side global
// table. We hand-unroll what the [container] macro would inject (PushID via
// widget_prelude + container_path_push/pop) instead of using the annotation,
// precisely to drop the macro's auto-state-global + indexed-table requirement.
// Registration is a per-frame entry whose payload is the id (+ bbox queried
// from the editor for nodes); container_finalize with null (state_addr, ti)
// keeps our hand-built payload (no reflection, no g_widgets meta to clobber it).

def private finalize_entity(widget_ident : string; kind : string; var entry : WidgetEntry) {
    //! Register a per-frame entry with a pre-built payload — null (addr, ti) so
    //! the snapshot uses entry.payload verbatim instead of reflecting a struct.
    container_finalize(widget_ident, kind, entry, null, null)
}

def node(id : NodeId; blk : block) {
    //! A graph node — `node(id){…}`. `id` is the editor's node handle. Registers
    //! as kind "node" with payload {id, bbox}; bbox is queried from the editor
    //! (GetNodePosition/GetNodeSize) — the editor owns node geometry, not ImGui's
    //! item rect. Child pins/text nest under this node's path.
    let ident = "node_{id}"
    widget_prelude(ident)
    container_path_push(ident)
    imgui_node_editor::BeginNode(id)
    invoke(blk)
    imgui_node_editor::EndNode()
    var entry : WidgetEntry
    let pos = imgui_node_editor::GetNodePosition(id)
    let sz = imgui_node_editor::GetNodeSize(id)
    entry.bbox = float4(pos.x, pos.y, pos.x + sz.x, pos.y + sz.y)
    entry.payload = JV((id = id, bbox = entry.bbox, selected = imgui_node_editor::IsNodeSelected(id)))
    finalize_entity(ident, "node", entry)
    container_path_pop()
}

def pin(id : PinId; kind : PinKind; blk : block) {
    //! A node pin — `pin(id, kind){…}`. Registers as kind "pin" with {id, kind}.
    //! (imgui-node-editor exposes no pin-geometry query, so bbox stays empty.)
    let ident = "pin_{id}"
    widget_prelude(ident)
    container_path_push(ident)
    imgui_node_editor::BeginPin(id, kind)
    invoke(blk)
    imgui_node_editor::EndPin()
    var entry : WidgetEntry
    entry.payload = JV((id = id, kind = "{kind}"))
    finalize_entity(ident, "pin", entry)
    container_path_pop()
}

def link(id : LinkId; from : PinId; to : PinId;
         color : float4 = float4(1.0, 1.0, 1.0, 1.0); thickness : float = 1.0) {
    //! A graph edge — `link(id, from, to)`. Leaf (no body); the editor draws the
    //! curve. Registers as kind "link" with {id, from_pin, to_pin}. Color/thickness
    //! defaulted (the generated bind doesn't surface the C++ defaults).
    let ident = "link_{id}"
    widget_prelude(ident)
    container_path_push(ident)
    imgui_node_editor::Link(id, from, to, color, thickness)
    var entry : WidgetEntry
    entry.payload = JV((id = id, from_pin = from, to_pin = to, selected = imgui_node_editor::IsLinkSelected(id)))
    finalize_entity(ident, "link", entry)
    container_path_pop()
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
