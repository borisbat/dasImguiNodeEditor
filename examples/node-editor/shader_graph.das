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

def build_sample_graph(var g : Graph) {
    g.next_id = 1
    let tex  = add_node(g, NodeKind.TexInput,    "Texture",      float2(40.0,  40.0),  [], ["RGBA"])
    let tint = add_node(g, NodeKind.ConstInput,  "Tint",         float2(40.0,  220.0), [], ["Color"])
    let mul  = add_node(g, NodeKind.Mul,         "Multiply",     float2(340.0, 90.0),  ["A", "B"], ["Out"])
    let outp = add_node(g, NodeKind.ColorOutput, "Color Output", float2(640.0, 120.0), ["Color"], [])
    add_link(g, out_pin(g, tex,  0), in_pin(g, mul,  0))
    add_link(g, out_pin(g, tint, 0), in_pin(g, mul,  1))
    add_link(g, out_pin(g, mul,  0), in_pin(g, outp, 0))
}

// ===== app toolbar (create / delete; app-specific, nothing generic) =====

def toolbar() {
    if (button((text = "Add Node"))) {
        let pos = float2(480.0 + float(g_spawn % 6) * 28.0, 380.0 + float(g_spawn % 6) * 28.0)
        g_spawn = g_spawn + 1
        let nid = add_node(g_graph, NodeKind.Mul, "Node", pos, ["A", "B"], ["Out"])
        set_node_position(g_ed, nid, pos)
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

def draw_editor(var g : Graph) {
    node_editor(g_ed, "shader_graph") {
        g_dbg_canvas = imgui_node_editor::GetScreenSize()
        g_dbg_zoom = imgui_node_editor::GetCurrentZoom()
        g_dbg_s_origin = imgui_node_editor::CanvasToScreen(float2(0.0, 0.0))
        g_dbg_s_far = imgui_node_editor::CanvasToScreen(float2(1000.0, 1000.0))
        for (n in values(g.nodes)) {
            // Seed the initial position ONCE. After that the editor owns it
            // (user drags, move_node command) — we never re-push from Node.pos.
            if (g_nav_frames == 0) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
            }
            node(n.id) {
                text("{n.title}")
                for (p in n.inputs) {
                    pin(p.id, PinKind.Input) {
                        text("-> {p.name}")
                    }
                }
                for (p in n.outputs) {
                    pin(p.id, PinKind.Output) {
                        text("{p.name} ->")
                    }
                }
            }
        }
        for (l in values(g.links)) {
            link(l.id, l.from_pin, l.to_pin)
        }

        begin_create(g_ed) {
            var a = 0
            var b = 0
            if (query_new_link(g_ed, a, b)) {
                if (a != 0 && b != 0) {
                    // Validity gates accept-vs-reject (called every frame); accept's
                    // bool return gates the actual commit.
                    if (valid_link(g, a, b)) {
                        if (accept_new_item(g_ed)) {
                            add_link(g, a, b)
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
                if (accept_deleted_item(g_ed)) {
                    g.links |> erase(lid)
                }
            }
            var nid = 0
            while (query_deleted_node(g_ed, nid)) {
                if (accept_deleted_item(g_ed)) {
                    remove_node(g, nid)
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
        draw_editor(g_graph)
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
