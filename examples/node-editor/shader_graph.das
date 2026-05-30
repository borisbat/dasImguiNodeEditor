options gen2

// Data-driven shader-graph editor. The app owns the graph TOPOLOGY (a cohesive
// Graph struct: nodes own their pins, links connect pins) — this mirrors real
// user code. The editor owns node GEOMETRY: Node.pos is only an initial seed;
// once a node is placed (or the user drags it) the editor is authoritative and
// nothing reads the position back. So `move_node` is a thin live command that
// just calls SetNodePosition — no graph round-trip.

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live
require imgui/imgui_node_editor_theme_daslang
require daslib/json
require daslib/json_boost

// ===== shader-graph model (app-owned topology) =====

enum NodeKind { TexInput, ConstInput, Mul, Add, ColorOutput }

struct Pin {
    id   : int
    name : string
}

struct Node {
    id      : int
    kind    : NodeKind
    title   : string
    pos     : float2                 // INITIAL position only; editor owns it after placement
    inputs  : array<Pin>
    outputs : array<Pin>
}

struct Link {
    id       : int
    from_pin : int
    to_pin   : int
}

// A group / comment box — a pin-less node that visually corrals the nodes dragged
// onto it (they move with the group). Geometry is editor-owned after the initial
// seed, exactly like Node.pos.
struct GroupBox {
    id    : int
    title : string
    pos   : float2          // INITIAL position only
    size  : float2          // content size passed to group()
}

struct Graph {
    nodes   : table<int; Node>
    groups  : table<int; GroupBox>
    links   : table<int; Link>
    next_id : int
}

var g_graph : Graph
var g_ed : imgui_node_editor::EditorContext? = null    // app owns the editor context(s)
var g_spawn : int = 0                                  // cascade offset for newly-added nodes
var g_seeded : table<int>                              // node ids whose initial position has been pushed to the editor
var g_dbg_canvas   : float2
var g_dbg_zoom     : float
var g_request_navigate : bool = false                  // fit-to-content requested (startup + navigate_to_content live command)
var g_did_startup_fit : bool = false                   // one-shot guard: fit the initial graph once it has laid out
var g_ctx_node : int = 0                               // node under a right-click (node context menu)
var g_ctx_link : int = 0                               // link under a right-click (link context menu)
var g_ctx_pos  : float2                                // canvas pos to place a context-menu-created node
var g_drag_from_pin : int = 0                          // source pin of a node-by-drag; 0 = plain right-click (no auto-connect)
var g_last_link : int = 0                              // most-recently connected link — auto-flows each frame (draw_editor)
var g_shortcut_action = ""                             // clipboard shortcut accepted this frame; handled AFTER the node_editor block

var g_paste_anchor : float2                            // canvas pos captured at accept_paste (cursor) — where paste lands

// App-owned clipboard. The editor owns no clipboard content — accept_copy/cut just say
// "a copy happened"; the app captures the selected cluster here: node kinds + RELATIVE
// positions, plus the links INTERNAL to the selection (by node-index + pin-slot, so they
// remap to the fresh pin ids on paste). Paste recreates the cluster preserving layout.
struct ClipNode {
    kind  : NodeKind
    title : string
    rel   : float2          // position relative to the copied cluster's top-left (g_clip_origin)
}
struct ClipLink {
    from_idx  : int         // index into g_clip_nodes (source node)
    from_slot : int         // which OUTPUT pin of that node
    to_idx    : int         // index into g_clip_nodes (dest node)
    to_slot   : int         // which INPUT pin of that node
}
var g_clip_nodes  : array<ClipNode>
var g_clip_links  : array<ClipLink>
var g_clip_origin : float2                             // top-left of the copied cluster (duplicate offsets off this)

// Per-id NarrativeState slots for the loop-rendered title / pin-name text().
// The plain text("foo") form shares ONE state global per source line, so every
// loop iteration overwrites it and the snapshot collapses every node's value to
// the last one rendered. Indexed text(TABLE[id], …) gives each id its own slot
// (the data_table.das idiom) so per-node/per-pin telemetry is correct.
var NODE_TITLE : table<int; NarrativeState>            // keyed by node id
var PIN_LABEL  : table<int; NarrativeState>            // keyed by pin id (input + output ids are disjoint)
var GROUP_TITLE : table<int; NarrativeState>          // keyed by group id (disjoint — shared alloc_id)

// ===== graph construction =====

def alloc_id(var g : Graph) : int {
    let id = g.next_id
    g.next_id = g.next_id + 1
    return id
}

def add_node(var g : Graph; kind : NodeKind; title : string; pos : float2;
             ins : array<string>; outs : array<string>) : int {
    let nid = alloc_id(g)
    var n = Node(id = nid, kind = kind, title = title, pos = pos)
    n.inputs |> reserve(length(ins))
    for (nm in ins) {
        n.inputs |> emplace(Pin(id = alloc_id(g), name = nm))
    }
    n.outputs |> reserve(length(outs))
    for (nm in outs) {
        n.outputs |> emplace(Pin(id = alloc_id(g), name = nm))
    }
    g.nodes[nid] <- n
    return nid
}

def add_group(var g : Graph; title : string; pos : float2; size : float2) : int {
    let gid = alloc_id(g)
    g.groups[gid] = GroupBox(id = gid, title = title, pos = pos, size = size)
    return gid
}

def out_pin(var g : Graph; nid : int; i : int) : int {
    return g.nodes[nid].outputs[i].id
}

def in_pin(var g : Graph; nid : int; i : int) : int {
    return g.nodes[nid].inputs[i].id
}

def pin_is_output(var g : Graph; pid : int) : bool {
    for (n in values(g.nodes)) {
        for (p in n.outputs) {
            return true if (p.id == pid)
        }
    }
    return false
}

def pin_node(var g : Graph; pid : int) : int {
    // Node that owns pin `pid` (0 = not found).
    for (n in values(g.nodes)) {
        for (p in n.inputs) {
            return n.id if (p.id == pid)
        }
        for (p in n.outputs) {
            return n.id if (p.id == pid)
        }
    }
    return 0
}

def pin_slot(var g : Graph; pid : int) : int {
    // Index of pin `pid` within its node's output (or input) list — the stable slot a
    // clipboard link records so it remaps to the pasted node's fresh pin id.
    for (n in values(g.nodes)) {
        for (i in range(length(n.outputs))) {
            return i if (n.outputs[i].id == pid)
        }
        for (i in range(length(n.inputs))) {
            return i if (n.inputs[i].id == pid)
        }
    }
    return 0
}

def link_exists(var g : Graph; out_pid : int; in_pid : int) : bool {
    // A link already connects this exact output -> input pair (dedupe guard).
    for (l in values(g.links)) {
        return true if (l.from_pin == out_pid && l.to_pin == in_pid)
    }
    return false
}

def remove_link_on_input(var g : Graph; in_pid : int) {
    // Inputs are single-connection: drop any existing link feeding this input
    // (replace-on-reconnect). At most one given the rule, but scan defensively.
    var dead = 0
    for (l in values(g.links)) {
        if (l.to_pin == in_pid) {
            dead = l.id
        }
    }
    if (dead != 0) {
        g.links |> erase(dead)
    }
}

def creates_cycle(var g : Graph; src_node : int; dst_node : int) : bool {
    // Would adding src_node -> dst_node form a cycle? It would iff dst_node can already
    // reach src_node downstream (dst is upstream of src). Shader graphs must stay DAGs.
    return true if (src_node == dst_node)
    var stack : array<int>
    stack |> push(dst_node)
    var seen : table<int>
    var hit = false
    while (!empty(stack) && !hit) {
        let cur = stack[length(stack) - 1]
        stack |> erase(length(stack) - 1)
        if (!key_exists(seen, cur)) {
            seen |> insert(cur)
            if (cur == src_node) {
                hit = true
            } else {
                for (l in values(g.links)) {
                    if (pin_node(g, l.from_pin) == cur) {
                        let nxt = pin_node(g, l.to_pin)
                        if (nxt != 0) {
                            stack |> push(nxt)
                        }
                    }
                }
            }
        }
    }
    delete stack
    delete seen
    return hit
}

def can_add_link(var g : Graph; out_pid : int; in_pid : int) : bool {
    // Caller normalizes so out_pid is an output, in_pid an input. Rejects self-loops,
    // duplicate pairs, and cycle-forming links. Input OCCUPANCY is not a block here — the
    // create handler replaces an existing link on the input (single fan-in, last-wins).
    let src = pin_node(g, out_pid)
    let dst = pin_node(g, in_pid)
    return !(src == 0 || dst == 0 || src == dst
          || link_exists(g, out_pid, in_pid) || creates_cycle(g, src, dst))
}

def add_link(var g : Graph; from_pin : int; to_pin : int) {
    let lid = alloc_id(g)
    g.links[lid] = Link(id = lid, from_pin = from_pin, to_pin = to_pin)
    g_last_link = lid    // demo: the most-recently connected link auto-flows (see draw_editor)
}

def remove_node(var g : Graph; nid : int) {
    // A group is a node to the editor, so begin_delete reports its id here too.
    if (key_exists(g.groups, nid)) {
        g.groups |> erase(nid)
        return
    }
    return if (!key_exists(g.nodes, nid))
    var dead_pins : table<int>
    for (p in g.nodes[nid].inputs) {
        dead_pins |> insert(p.id)
    }
    for (p in g.nodes[nid].outputs) {
        dead_pins |> insert(p.id)
    }
    g.nodes |> erase(nid)
    var link_ids <- [for (lk in keys(g.links)); lk]
    for (lk in link_ids) {
        let l = g.links[lk]
        if (key_exists(dead_pins, l.from_pin) || key_exists(dead_pins, l.to_pin)) {
            g.links |> erase(lk)
        }
    }
    delete dead_pins
    delete link_ids
}

def spawn_node(var g : Graph; kind : NodeKind; pos : float2) : int {
    // The single place that knows each kind's title + pin layout — shared by the
    // sample graph, the toolbar buttons, and the right-click context menu.
    return add_node(g, kind, "Texture",      pos, [], ["RGBA"]) if (kind == NodeKind.TexInput)
    return add_node(g, kind, "Tint",         pos, [], ["Color"]) if (kind == NodeKind.ConstInput)
    return add_node(g, kind, "Add",          pos, ["A", "B"], ["Out"]) if (kind == NodeKind.Add)
    return add_node(g, kind, "Color Output", pos, ["Color"], []) if (kind == NodeKind.ColorOutput)
    return add_node(g, kind, "Multiply",     pos, ["A", "B"], ["Out"])  // Mul
}

def build_sample_graph(var g : Graph) {
    g.next_id = 1
    let tex  = spawn_node(g, NodeKind.TexInput,    float2(40.0,  40.0))
    let tint = spawn_node(g, NodeKind.ConstInput,  float2(40.0,  220.0))
    let mul  = spawn_node(g, NodeKind.Mul,         float2(340.0, 90.0))
    let outp = spawn_node(g, NodeKind.ColorOutput, float2(640.0, 120.0))
    add_link(g, out_pin(g, tex,  0), in_pin(g, mul,  0))
    add_link(g, out_pin(g, tint, 0), in_pin(g, mul,  1))
    add_link(g, out_pin(g, mul,  0), in_pin(g, outp, 0))
}

// ===== app toolbar (create / delete; app-specific, nothing generic) =====

def toolbar_spawn(kind : NodeKind) {
    // Cascade-place toolbar-created nodes. Runs OUTSIDE the node_editor block, so
    // the bracketed set_node_position (SetCurrentEditor…null) is the right call.
    let pos = float2(480.0 + float(g_spawn % 6) * 28.0, 380.0 + float(g_spawn % 6) * 28.0)
    g_spawn = g_spawn + 1
    let nid = spawn_node(g_graph, kind, pos)
    set_node_position(g_ed, nid, pos)
}

def spawn_group(title : string; pos : float2; size : float2) : int {
    // Both pos and size are ONE-TIME seeds — the editor owns group geometry after the first
    // frame. node_group passes gr.size only until the node becomes a group; thereafter the
    // editor's stored bounds win and gr.size is ignored. pos seeded via the bracketed
    // set_node_position (toolbar runs outside the node_editor block); to resize a group
    // later, call set_group_size — mutating GroupBox.size alone won't do it.
    let gid = add_group(g_graph, title, pos, size)
    set_node_position(g_ed, gid, pos)
    return gid
}

def toolbar() {
    if (button((text = "+ Texture"))) {
        toolbar_spawn(NodeKind.TexInput)
    }
    same_line()
    if (button((text = "+ Tint"))) {
        toolbar_spawn(NodeKind.ConstInput)
    }
    same_line()
    if (button((text = "+ Multiply"))) {
        toolbar_spawn(NodeKind.Mul)
    }
    same_line()
    if (button((text = "+ Add"))) {
        toolbar_spawn(NodeKind.Add)
    }
    same_line()
    if (button((text = "+ Output"))) {
        toolbar_spawn(NodeKind.ColorOutput)
    }
    same_line()
    if (button((text = "+ Group"))) {
        let pos = float2(480.0 + float(g_spawn % 6) * 28.0, 380.0 + float(g_spawn % 6) * 28.0)
        g_spawn = g_spawn + 1
        spawn_group("Group", pos, float2(220.0, 160.0))
    }
    same_line()
    if (button((text = "Delete Selected Node"))) {
        var sel <- get_selected_nodes(g_ed)
        for (nid in sel) {
            remove_node(g_graph, nid)
        }
        delete sel
    }
    same_line()
    if (button((text = "Delete Selected Link"))) {
        var sel <- get_selected_links(g_ed)
        for (lid in sel) {
            g_graph.links |> erase(lid)
        }
        delete sel
    }
    same_line()
    if (button((text = "Center Selected"))) {
        // View actions run outside the node_editor block → bracketed wrappers. (May
        // share NavigateToContent's SCALE_TO_MONITOR/DPI quirk; see g_request_navigate.)
        var sel <- get_selected_nodes(g_ed)
        if (!empty(sel)) {
            center_node_on_screen(g_ed, sel[0])
        }
        delete sel
    }
    same_line()
    if (button((text = "Frame Selection"))) {
        navigate_to_selection(g_ed, false, -1.0)
    }
}

// ===== render + interaction =====

def node_tint(kind : NodeKind) : float4 {
    // Per-kind node tint, fed to node()'s `color` tuple arg. Inputs green,
    // output red; math nodes pass a negative sentinel = keep the editor default.
    return float4(0.15, 0.35, 0.18, 0.78) if (kind == NodeKind.TexInput || kind == NodeKind.ConstInput)
    return float4(0.40, 0.18, 0.18, 0.78) if (kind == NodeKind.ColorOutput)
    return float4(-1.0, -1.0, -1.0, -1.0)
}

// Pin layout per kind — single source of truth shared by spawn_node, the menu
// filter (connectable), and connect-on-select. (TexInput/ConstInput are sources:
// out only; ColorOutput is a sink: in only; Add/Mul are both.)
def kind_has_input(kind : NodeKind) : bool {
    return kind == NodeKind.Add || kind == NodeKind.Mul || kind == NodeKind.ColorOutput
}

def kind_has_output(kind : NodeKind) : bool {
    return kind == NodeKind.TexInput || kind == NodeKind.ConstInput || kind == NodeKind.Add || kind == NodeKind.Mul
}

def connectable(kind : NodeKind) : bool {
    // Plain right-click (no source pin) → every kind. Drag from a pin → only kinds
    // that can connect: source output needs a kind with an input, and vice-versa.
    return true if (g_drag_from_pin == 0)
    return pin_is_output(g_graph, g_drag_from_pin) ? kind_has_input(kind) : kind_has_output(kind)
}

def ctx_spawn(kind : NodeKind) {
    // Spawn the chosen kind at the gesture point. Runs INSIDE the node_editor block
    // (editor already current) → raw SetNodePosition, not the bracketed wrapper.
    let nid = spawn_node(g_graph, kind, g_ctx_pos)
    imgui_node_editor::SetNodePosition(nid, g_ctx_pos)
    // Came from a pin-drag → auto-connect source to the new node's compatible pin.
    // The menu was filtered to connectable kinds, so the target pin always exists.
    // enqueue_new_link is order-sensitive (output -> input); valid_link enforces it.
    if (g_drag_from_pin != 0) {
        if (pin_is_output(g_graph, g_drag_from_pin)) {
            enqueue_new_link(g_ed, g_drag_from_pin, in_pin(g_graph, nid, 0))
        } else {
            enqueue_new_link(g_ed, out_pin(g_graph, nid, 0), g_drag_from_pin)
        }
        g_drag_from_pin = 0
    }
}

def render_node_body(n : Node) {
    // Shared by the plain + output-node render paths. Pin pivots place the link-attach
    // point on the node's edge — inputs on the left, outputs on the right — so links
    // leave/arrive cleanly instead of from the pin's center.
    text(NODE_TITLE[n.id], (text = n.title))
    for (p in n.inputs) {
        pin(p.id, (kind = PinKind.Input, pivot_alignment = float2(0.0, 0.5))) {
            text(PIN_LABEL[p.id], (text = "-> {p.name}"))
        }
    }
    for (p in n.outputs) {
        // pivot_scale enlarges the output pin's attach area a touch (the third pivot knob,
        // alongside alignment + size) so links spring from a slightly wider anchor.
        pin(p.id, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5), pivot_scale = float2(1.25, 1.25))) {
            text(PIN_LABEL[p.id], (text = "{p.name} ->"))
        }
    }
}

// Single-graph demo: the app owns ONE Graph (g_graph) and ONE editor (g_ed), so
// draw_editor + the toolbar/context-menu spawn helpers all act on those globals.
// A multi-graph app would thread its Graph + ctx through these instead.
def draw_editor() {
    node_editor("shader_graph", (editor = g_ed, size = float2(0.0, 0.0))) {
        g_dbg_canvas = imgui_node_editor::GetScreenSize()
        g_dbg_zoom = imgui_node_editor::GetCurrentZoom()
        // Groups draw first so regular nodes sit on top of them. A group is a pin-less
        // node (group() = BeginNode + Group(size)); its title labels the box.
        for (gr in values(g_graph.groups)) {
            node_group(gr.id, (size = gr.size)) {
                text(GROUP_TITLE[gr.id], (text = gr.title))
            }
        }
        // Off-screen group labels: when the canvas is zoomed out (scale <= 0.75) the editor
        // renders a hint overlay so group names stay readable. group_hint self-gates (no-op
        // at normal zoom), so the loop is unconditional. Drawn into the hint draw lists,
        // positioned at the group's canvas bounds (GetGroupMin — an allow-listed read).
        for (gr in values(g_graph.groups)) {
            group_hint(gr.id) $(var fg; var _bg) {
                // Float the group title above the group bounds (GetGroupMin is in screen space
                // inside a hint). _bg is the background hint list — unused here, exposed for
                // callers that want art drawn behind the group. NB: the hint draw lists swap
                // R/B for asymmetric colors, so use a near-grey (swap-invariant) label tint.
                let mn = imgui_node_editor::GetGroupMin()
                fg |> add_text(float2(mn.x + 4.0, mn.y - 18.0), rgba(232u, 226u, 210u, 255u), gr.title)
            }
        }
        for (n in values(g_graph.nodes)) {
            // Seed each node's initial position ONCE, inside the frame right before its
            // BeginNode — the only reliable time. An out-of-frame SetNodePosition (e.g. from
            // the paste handler, which runs after this block) on a not-yet-rendered node does
            // NOT commit headless: GetNodePosition keeps returning the un-laid-out sentinel.
            // Gating on a per-node seeded set (not frame 0) covers paste/toolbar/menu nodes too;
            // after the first render the editor owns geometry (user drags, move_node command).
            if (!key_exists(g_seeded, n.id)) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
                g_seeded |> insert(n.id)
            }
            if (n.kind == NodeKind.ColorOutput) {
                // The output node showcases per-node rendering config: rounded corners via
                // a scoped style var, plus an amber border via a scoped style color (the two
                // compose — with_style_color is the color peer of with_style_var).
                with_style_var(imgui_node_editor::StyleVar.NodeRounding, 10.0) {
                    with_style_color(imgui_node_editor::StyleColor.NodeBorder, float4(0.910, 0.631, 0.227, 1.0)) {
                        node(n.id, (color = node_tint(n.kind))) {
                            render_node_body(n)
                        }
                    }
                }
                // A custom accent stripe on its own background draw list — drawn AFTER the
                // node block (the node's draw channels only exist once it's fully built).
                with_node_background_drawlist(n.id) $(var dl) {
                    let p = imgui_node_editor::GetNodePosition(n.id)
                    let s = imgui_node_editor::GetNodeSize(n.id)
                    dl |> add_rect_filled(p, float2(p.x + 5.0, p.y + s.y), rgba(255u, 90u, 90u, 220u))
                }
            } else {
                node(n.id, (color = node_tint(n.kind))) {
                    render_node_body(n)
                }
            }
        }
        for (l in values(g_graph.links)) {
            link(l.id, (from = l.from_pin, to = l.to_pin))
        }

        // Set when a pin-drag is released in empty canvas this frame (see below) —
        // opens the SAME create-node popup as a right-click, with g_drag_from_pin set
        // so the pick also connects. Frame-local: begin_create writes it, with_suspended
        // reads it.
        var drag_fired = false
        begin_create(g_ed) {
            var a = 0
            var b = 0
            if (query_new_link(g_ed, a, b)) {
                if (a != 0 && b != 0) {
                    // Pins come in DRAG order — normalize so `from` is the output, `to` the
                    // input (reversed if the user dragged input -> output). Reject same-kind
                    // pairs outright; can_add_link gates self-loops / duplicates / cycles.
                    // Validity gates accept-vs-reject each frame; accept's bool return gates
                    // the actual commit, where we replace any existing link on the input.
                    if (pin_is_output(g_graph, a) == pin_is_output(g_graph, b)) {
                        reject_new_item(g_ed)
                    } else {
                        let from = pin_is_output(g_graph, a) ? a : b
                        let to = pin_is_output(g_graph, a) ? b : a
                        if (can_add_link(g_graph, from, to)) {
                            if (accept_new_item(g_ed)) {
                                remove_link_on_input(g_graph, to)
                                add_link(g_graph, from, to)
                            }
                        } else {
                            reject_new_item(g_ed)
                        }
                    }
                }
            }
            // Drag from a pin into empty canvas → records g_drag_from_pin + g_ctx_pos.
            if (show_new_node_drag(g_ed, g_drag_from_pin, g_ctx_pos)) {
                drag_fired = true
            }
        }

        begin_delete(g_ed) {
            var lid = 0
            while (query_deleted_link(g_ed, lid)) {
                if (accept_deleted_link(g_ed)) {
                    g_graph.links |> erase(lid)
                }
            }
            var nid = 0
            while (query_deleted_node(g_ed, nid)) {
                if (accept_deleted_node(g_ed)) {
                    remove_node(g_graph, nid)
                }
            }
        }

        // Clipboard / edit shortcuts (Ctrl+C/X/V/D — on by default per create_node_editor).
        // accept_* only flags the action here (editor is current); the actual copy/paste runs
        // AFTER the block (handle_shortcut_action) where the bracketed selection/spawn helpers
        // are safe. Mirrors the g_request_navigate flag-then-act pattern.
        with_shortcuts(g_ed) {
            if (accept_copy(g_ed)) {
                g_shortcut_action = "copy"
            } elif (accept_cut(g_ed)) {
                g_shortcut_action = "cut"
            } elif (accept_paste(g_ed)) {
                g_shortcut_action = "paste"
                // Capture the cursor in canvas space NOW (editor is current; ScreenToCanvas
                // needs it). handle_shortcut_action runs post-block where it'd be unavailable.
                // Guard the mouse: a keyboard Ctrl+V with no on-canvas cursor (and every headless
                // frame, where IsMousePosValid is false) yields a -FLT_MAX GetMousePos, which
                // ScreenToCanvas turns into a garbage anchor. Fall back to just past the copied
                // cluster — the same offset duplicate uses.
                g_paste_anchor = (is_mouse_pos_valid()
                    ? imgui_node_editor::ScreenToCanvas(GetMousePos())
                    : g_clip_origin + float2(30.0, 30.0))
            } elif (accept_duplicate(g_ed)) {
                g_shortcut_action = "duplicate"
            }
        }

        // Right-click context menus. Detection + popups run in a Suspend/Resume
        // island (screen space) per imgui-node-editor: background → create a node
        // of the chosen kind at the cursor; node/link → delete.
        with_suspended() {
            var nid = 0
            var lid = 0
            if (drag_fired) {
                // Pin-drag release → same create-node popup; g_drag_from_pin is set so
                // the pick connects (menu filtered to connectable kinds).
                open_popup("ne_bg_menu")
            } elif (show_node_context_menu(g_ed, nid)) {
                g_ctx_node = nid
                open_popup("ne_node_menu")
            } elif (show_link_context_menu(g_ed, lid)) {
                g_ctx_link = lid
                open_popup("ne_link_menu")
            } elif (show_background_context_menu(g_ed, g_ctx_pos)) {
                g_drag_from_pin = 0    // plain right-click → no source pin, no auto-connect
                open_popup("ne_bg_menu")
            }
            popup_window(NODE_CTX, (str_id = "ne_node_menu", flags = ImGuiWindowFlags.None)) {
                if (menu_label(DEL_NODE, (text = "Delete Node"))) {
                    remove_node(g_graph, g_ctx_node)
                }
            }
            popup_window(LINK_CTX, (str_id = "ne_link_menu", flags = ImGuiWindowFlags.None)) {
                if (menu_label(DEL_LINK, (text = "Delete Link"))) {
                    g_graph.links |> erase(g_ctx_link)
                }
            }
            // Explicit idents (CREATE_*) give the menu items stable snapshot paths
            // (MAIN_WIN/shader_graph/BG_CTX/CREATE_*). When opened by a pin-drag the
            // list is filtered to connectable kinds (connectable()), so a non-fitting
            // item is simply absent from the snapshot — which the test asserts.
            popup_window(BG_CTX, (str_id = "ne_bg_menu", flags = ImGuiWindowFlags.None)) {
                if (g_drag_from_pin != 0) {
                    text("Create + Connect")
                } else {
                    text("Create Node")
                }
                if (connectable(NodeKind.TexInput) && menu_label(CREATE_TEX, (text = "Texture"))) {
                    ctx_spawn(NodeKind.TexInput)
                }
                if (connectable(NodeKind.ConstInput) && menu_label(CREATE_TINT, (text = "Tint"))) {
                    ctx_spawn(NodeKind.ConstInput)
                }
                if (connectable(NodeKind.Mul) && menu_label(CREATE_MUL, (text = "Multiply"))) {
                    ctx_spawn(NodeKind.Mul)
                }
                if (connectable(NodeKind.Add) && menu_label(CREATE_ADD, (text = "Add"))) {
                    ctx_spawn(NodeKind.Add)
                }
                if (connectable(NodeKind.ColorOutput) && menu_label(CREATE_OUT, (text = "Color Output"))) {
                    ctx_spawn(NodeKind.ColorOutput)
                }
            }
        }

        // Fit-on-startup: once the initial graph has laid out (node bounds are valid only
        // after a node's first render — see the seeding note above), fit it to the view.
        // Also serviced by the navigate_to_content live command. NavigateToContent must run
        // with the editor current — here, inside the node_editor block.
        if (!g_did_startup_fit && !empty(g_seeded)) {
            g_request_navigate = true
            g_did_startup_fit = true
        }
        if (g_request_navigate) {
            imgui_node_editor::NavigateToContent(0.0)
            g_request_navigate = false
        }
    }
    // Continuous flow on the most-recently connected link. Called AFTER the
    // node_editor block (editor no longer current) so flow()'s SetCurrentEditor
    // bracket is safe; re-arming every frame keeps the pulse alive. Forward only.
    if (g_last_link != 0) {
        flow(g_ed, g_last_link)
    }
    // Apply any clipboard shortcut accepted this frame — here, post-block, the bracketed
    // get_selected_nodes / set_node_position / select_node helpers are safe to call.
    handle_shortcut_action(g_ed)
}

// ===== clipboard / shortcuts (app owns the clipboard content) =====

def clipboard_copy(ctx : imgui_node_editor::EditorContext?) {
    // Capture the selected cluster: node kinds + positions relative to the cluster's
    // top-left (g_clip_origin), and the links whose BOTH endpoints are selected (recorded
    // by node-index + pin-slot so they remap onto the pasted nodes' fresh pin ids).
    var sel <- get_selected_nodes(ctx)
    g_clip_nodes |> clear()
    g_clip_links |> clear()
    // Pass 1: gather real nodes (skip group ids) + their editor positions; track the min corner.
    var ids : array<int>
    var poss : array<float2>
    var origin = float2(1.0e9, 1.0e9)
    for (nid in sel) {
        continue if (!key_exists(g_graph.nodes, nid))
        let p = get_node_position(ctx, nid)
        ids |> push(nid)
        poss |> push(p)
        if (p.x < origin.x) {
            origin.x = p.x
        }
        if (p.y < origin.y) {
            origin.y = p.y
        }
    }
    g_clip_origin = empty(ids) ? float2(0.0, 0.0) : origin
    // Pass 2: clip nodes (relative layout) + a node-id -> clip-index map for link capture.
    var node_to_clipidx : table<int; int>
    for (i in range(length(ids))) {
        let nid = ids[i]
        let knd = g_graph.nodes[nid].kind
        let ttl = g_graph.nodes[nid].title
        node_to_clipidx[nid] = i
        g_clip_nodes |> push(ClipNode(kind = knd, title = ttl, rel = poss[i] - g_clip_origin))
    }
    // Internal links (both endpoints in the selection). Links are normalized (from=output).
    for (l in values(g_graph.links)) {
        let fn = pin_node(g_graph, l.from_pin)
        let tn = pin_node(g_graph, l.to_pin)
        if (key_exists(node_to_clipidx, fn) && key_exists(node_to_clipidx, tn)) {
            let fi = node_to_clipidx[fn]
            let ti = node_to_clipidx[tn]
            g_clip_links |> push(ClipLink(from_idx = fi, from_slot = pin_slot(g_graph, l.from_pin),
                                          to_idx = ti, to_slot = pin_slot(g_graph, l.to_pin)))
        }
    }
    delete ids
    delete poss
    delete node_to_clipidx
    delete sel
}

def clipboard_paste(ctx : imgui_node_editor::EditorContext?; anchor : float2) {
    // Recreate the clipboard cluster with its top-left at `anchor`, preserving relative
    // layout, then re-link the internal edges onto the fresh pins. Pasted nodes come in
    // selected so a follow-up paste/duplicate chains off them.
    return if (empty(g_clip_nodes))
    clear_selection(ctx)
    var idx_to_new : table<int; int>
    for (i in range(length(g_clip_nodes))) {
        let ce = g_clip_nodes[i]
        let pos = anchor + ce.rel
        let nid = spawn_node(g_graph, ce.kind, pos)
        set_node_position(ctx, nid, pos)
        select_node(ctx, nid, true)
        idx_to_new[i] = nid
    }
    for (cl in g_clip_links) {
        let fn = idx_to_new[cl.from_idx]
        let tn = idx_to_new[cl.to_idx]
        add_link(g_graph, out_pin(g_graph, fn, cl.from_slot), in_pin(g_graph, tn, cl.to_slot))
    }
    delete idx_to_new
}

def handle_shortcut_action(ctx : imgui_node_editor::EditorContext?) {
    if (g_shortcut_action == "copy") {
        clipboard_copy(ctx)
    } elif (g_shortcut_action == "cut") {
        clipboard_copy(ctx)
        var sel <- get_selected_nodes(ctx)
        for (nid in sel) {
            remove_node(g_graph, nid)
        }
        delete sel
    } elif (g_shortcut_action == "paste") {
        clipboard_paste(ctx, g_paste_anchor)    // at the cursor (captured at accept_paste)
    } elif (g_shortcut_action == "duplicate") {
        clipboard_copy(ctx)
        clipboard_paste(ctx, g_clip_origin + float2(30.0, 30.0))    // near the originals, layout preserved
    }
    g_shortcut_action = ""
}

// ===== app lifecycle =====

[export]
def init() {
    harness_init("Shader Graph — node editor", 1280, 720)
    g_ed = create_node_editor()
    apply_daslang_node_editor_style(g_ed)    // warm-dark + amber canvas to match the daslang ImGui theme
    build_sample_graph(g_graph)
}

[export]
def update() {
    if (!harness_begin_frame()) return
    harness_new_frame()
    // Fullscreen borderless host window (the imgui-node-editor framework pattern).
    let io & = unsafe(GetIO())
    SetNextWindowPos(float2(0.0, 0.0), ImGuiCond.Always)
    SetNextWindowSize(io.DisplaySize, ImGuiCond.Always)
    let flags = (ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize |
                 ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoScrollbar |
                 ImGuiWindowFlags.NoScrollWithMouse | ImGuiWindowFlags.NoSavedSettings |
                 ImGuiWindowFlags.NoBringToFrontOnFocus)
    window(MAIN_WIN, (text = "Shader Graph", closable = false, flags = flags)) {
        toolbar()
        draw_editor()
    }
    harness_end_frame()
}

[export]
def shutdown() {
    destroy_node_editor(g_ed)
    harness_shutdown()
}

[live_command(description = "Fit the view to all content (NavigateToContent), applied next frame inside the editor block.")]
def navigate_to_content(_input : JsonValue?) : JsonValue? {
    g_request_navigate = true
    return JV("queued")
}

[live_command(description = "Spawn a group/comment box: input title (string, optional), x, y, w, h (optional). Returns the new group id.")]
def spawn_group_cmd(input : JsonValue?) : JsonValue? {
    let title = input?["title"] ?? "Group"
    let x = input?["x"] ?? 480.0
    let y = input?["y"] ?? 380.0
    let w = input?["w"] ?? 220.0
    let h = input?["h"] ?? 160.0
    let gid = spawn_group(title, float2(x, y), float2(w, h))
    return JV((id = gid))
}

[live_command(description = "Spawn a node: input kind (\"tex\"|\"tint\"|\"mul\"|\"add\"|\"output\"), x, y. Returns the new node id (pins follow: Mul/Add = inA id+1, inB id+2, out id+3).")]
def spawn_node_cmd(input : JsonValue?) : JsonValue? {
    let kind_s = input?["kind"] ?? "mul"
    let x = input?["x"] ?? 200.0
    let y = input?["y"] ?? 200.0
    var k = NodeKind.Mul
    if (kind_s == "tex") {
        k = NodeKind.TexInput
    } elif (kind_s == "tint") {
        k = NodeKind.ConstInput
    } elif (kind_s == "add") {
        k = NodeKind.Add
    } elif (kind_s == "output") {
        k = NodeKind.ColorOutput
    }
    let nid = spawn_node(g_graph, k, float2(x, y))
    set_node_position(g_ed, nid, float2(x, y))
    return JV((id = nid))
}

[live_command(description = "Editor view + framebuffer dims. `zoom` is GetCurrentZoom = InvScale (1/scale): a zoomed-out view reads > 1, a zoomed-in view < 1.")]
def editor_dims(_input : JsonValue?) : JsonValue? {
    let io & = unsafe(GetIO())
    return JV((
        display_w = io.DisplaySize.x,
        display_h = io.DisplaySize.y,
        fb_scale_x = io.DisplayFramebufferScale.x,
        fb_scale_y = io.DisplayFramebufferScale.y,
        canvas_w = g_dbg_canvas.x,
        canvas_h = g_dbg_canvas.y,
        zoom = g_dbg_zoom
    ))
}

[export]
def main() {
    init()
    while (!exit_requested()) {
        update()
    }
    shutdown()
}
