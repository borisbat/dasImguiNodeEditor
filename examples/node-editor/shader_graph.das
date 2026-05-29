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

struct Graph {
    nodes   : table<int; Node>
    links   : table<int; Link>
    next_id : int
}

var g_graph : Graph
var g_ed : imgui_node_editor::EditorContext? = null    // app owns the editor context(s)
var g_spawn : int = 0                                  // cascade offset for newly-added nodes
var g_nav_frames : int = 0
var g_dbg_canvas   : float2
var g_dbg_zoom     : float
var g_dbg_s_origin : float2
var g_dbg_s_far    : float2
var g_request_navigate : bool = false
var g_ctx_node : int = 0                               // node under a right-click (node context menu)
var g_ctx_link : int = 0                               // link under a right-click (link context menu)
var g_ctx_pos  : float2                                // canvas pos to place a context-menu-created node

// Per-id NarrativeState slots for the loop-rendered title / pin-name text().
// The plain text("foo") form shares ONE state global per source line, so every
// loop iteration overwrites it and the snapshot collapses every node's value to
// the last one rendered. Indexed text(TABLE[id], …) gives each id its own slot
// (the data_table.das idiom) so per-node/per-pin telemetry is correct.
var NODE_TITLE : table<int; NarrativeState>            // keyed by node id
var PIN_LABEL  : table<int; NarrativeState>            // keyed by pin id (input + output ids are disjoint)

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

def valid_link(var g : Graph; a : int; b : int) : bool {
    // A link must join an output to an input — reject output->output / input->input.
    return pin_is_output(g, a) != pin_is_output(g, b)
}

def add_link(var g : Graph; from_pin : int; to_pin : int) {
    let lid = alloc_id(g)
    g.links[lid] = Link(id = lid, from_pin = from_pin, to_pin = to_pin)
}

def remove_node(var g : Graph; nid : int) {
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
}

// ===== render + interaction =====

def node_tint(kind : NodeKind) : float4 {
    // Per-kind node tint, fed to node()'s `color` tuple arg. Inputs green,
    // output red; math nodes pass a negative sentinel = keep the editor default.
    return float4(0.15, 0.35, 0.18, 0.78) if (kind == NodeKind.TexInput || kind == NodeKind.ConstInput)
    return float4(0.40, 0.18, 0.18, 0.78) if (kind == NodeKind.ColorOutput)
    return float4(-1.0, -1.0, -1.0, -1.0)
}

def ctx_spawn(kind : NodeKind) {
    // Create a node from the right-click menu, placed at the cursor. Runs INSIDE
    // the node_editor block (editor already current) → raw SetNodePosition, not
    // the SetCurrentEditor-bracketed wrapper.
    let nid = spawn_node(g_graph, kind, g_ctx_pos)
    imgui_node_editor::SetNodePosition(nid, g_ctx_pos)
}

// Single-graph demo: the app owns ONE Graph (g_graph) and ONE editor (g_ed), so
// draw_editor + the toolbar/context-menu spawn helpers all act on those globals.
// A multi-graph app would thread its Graph + ctx through these instead.
def draw_editor() {
    node_editor("shader_graph", (editor = g_ed, size = float2(0.0, 0.0))) {
        g_dbg_canvas = imgui_node_editor::GetScreenSize()
        g_dbg_zoom = imgui_node_editor::GetCurrentZoom()
        g_dbg_s_origin = imgui_node_editor::CanvasToScreen(float2(0.0, 0.0))
        g_dbg_s_far = imgui_node_editor::CanvasToScreen(float2(1000.0, 1000.0))
        for (n in values(g_graph.nodes)) {
            // Seed the initial position ONCE. After that the editor owns it
            // (user drags, move_node command) — we never re-push from Node.pos.
            if (g_nav_frames == 0) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
            }
            node(n.id, (color = node_tint(n.kind))) {
                text(NODE_TITLE[n.id], (text = n.title))
                for (p in n.inputs) {
                    pin(p.id, PinKind.Input) {
                        text(PIN_LABEL[p.id], (text = "-> {p.name}"))
                    }
                }
                for (p in n.outputs) {
                    pin(p.id, PinKind.Output) {
                        text(PIN_LABEL[p.id], (text = "{p.name} ->"))
                    }
                }
            }
        }
        for (l in values(g_graph.links)) {
            link(l.id, (from = l.from_pin, to = l.to_pin))
        }

        begin_create(g_ed) {
            var a = 0
            var b = 0
            if (query_new_link(g_ed, a, b)) {
                if (a != 0 && b != 0) {
                    // Validity gates accept-vs-reject (called every frame); accept's
                    // bool return gates the actual commit.
                    if (valid_link(g_graph, a, b)) {
                        if (accept_new_item(g_ed)) {
                            add_link(g_graph, a, b)
                        }
                    } else {
                        reject_new_item(g_ed)
                    }
                }
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

        // Right-click context menus. Detection + popups run in a Suspend/Resume
        // island (screen space) per imgui-node-editor: background → create a node
        // of the chosen kind at the cursor; node/link → delete.
        with_suspended() {
            var nid = 0
            var lid = 0
            if (show_node_context_menu(g_ed, nid)) {
                g_ctx_node = nid
                open_popup("ne_node_menu")
            } elif (show_link_context_menu(g_ed, lid)) {
                g_ctx_link = lid
                open_popup("ne_link_menu")
            } elif (show_background_context_menu(g_ed, g_ctx_pos)) {
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
            // (MAIN_WIN/shader_graph/BG_CTX/CREATE_*), which the context-menu test
            // asserts to confirm the menu opened on right-click.
            popup_window(BG_CTX, (str_id = "ne_bg_menu", flags = ImGuiWindowFlags.None)) {
                text("Create Node")
                if (menu_label(CREATE_TEX, (text = "Texture"))) {
                    ctx_spawn(NodeKind.TexInput)
                }
                if (menu_label(CREATE_TINT, (text = "Tint"))) {
                    ctx_spawn(NodeKind.ConstInput)
                }
                if (menu_label(CREATE_MUL, (text = "Multiply"))) {
                    ctx_spawn(NodeKind.Mul)
                }
                if (menu_label(CREATE_ADD, (text = "Add"))) {
                    ctx_spawn(NodeKind.Add)
                }
                if (menu_label(CREATE_OUT, (text = "Color Output"))) {
                    ctx_spawn(NodeKind.ColorOutput)
                }
            }
        }

        // NavigateToContent auto-call is DISABLED (DPI-broken under SCALE_TO_MONITOR,
        // see STATE.md). The `navigate_to_content` live command flips g_request_navigate.
        if (g_request_navigate) {
            imgui_node_editor::NavigateToContent(0.0)
            g_request_navigate = false
        }
        g_nav_frames = g_nav_frames + 1
    }
}

// ===== app lifecycle =====

[export]
def init() {
    harness_init("Shader Graph — node editor", 1280, 720)
    g_ed = create_node_editor()
    build_sample_graph(g_graph)
}

[export]
def update() {
    if (!harness_begin_frame()) return
    harness_apply_synth_io()    // drain synth mouse/key timelines (imgui_mouse_play etc.) + re-assert synth cursor over the real mouse
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

[live_command(description = "Trigger NavigateToContent on the editor (to observe the DPI bug)")]
def navigate_to_content(input : JsonValue?) : JsonValue? {
    g_request_navigate = true
    return JV("queued")
}

[live_command(description = "Editor display + framebuffer dimensions for debugging coverage")]
def editor_dims(input : JsonValue?) : JsonValue? {
    let io & = unsafe(GetIO())
    return JV((
        display_w = io.DisplaySize.x,
        display_h = io.DisplaySize.y,
        fb_scale_x = io.DisplayFramebufferScale.x,
        fb_scale_y = io.DisplayFramebufferScale.y,
        canvas_w = g_dbg_canvas.x,
        canvas_h = g_dbg_canvas.y,
        zoom = g_dbg_zoom,
        s_origin_x = g_dbg_s_origin.x,
        s_origin_y = g_dbg_s_origin.y,
        s_far_x = g_dbg_s_far.x,
        s_far_y = g_dbg_s_far.y
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
