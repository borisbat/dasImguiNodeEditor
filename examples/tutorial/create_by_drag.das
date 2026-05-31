options gen2

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: create_by_drag — drag from a pin into EMPTY canvas to create + connect.
//
//   begin_create(ed) {
//       if (query_new_link(ed, a, b)) { ... accept_new_item ... }   -- pin -> pin
//       if (show_new_node_drag(ed, from_pin, drop_pos)) {           -- pin -> empty
//           drag_fired = true                                        -- (remember source + pos)
//       }
//   }
//   with_suspended() {                                              -- popups in screen space
//       if (drag_fired) open_popup("...")
//       popup_window(...) { ... menu_label(...) -> spawn + enqueue_new_link ... }
//   }
//
// connect_by_drag taught the pin -> pin gesture. Releasing the SAME drag in empty
// canvas instead is the "create + connect" gesture: show_new_node_drag hands back the
// source pin + the canvas-space drop point, the app opens its create-node menu, and on
// a pick it spawns at the drop point and enqueue_new_link's the source to the new pin.
// The enqueued link replays through begin_create's query_new_link a frame later — the
// same path a hand-dragged link takes — so commit_link stores it once.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/create_by_drag.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/create_by_drag.das
// =============================================================================

struct Nd {
    id      : int
    title   : string
    in_pin  : int
    out_pin : int
    pos     : float2
}

struct Lk {
    id       : int
    from_pin : int
    to_pin   : int
}

var g_nodes    : table<int; Nd>
var g_links    : table<int; Lk>
var g_ed       : imgui_node_editor::EditorContext? = null
var g_seeded   : bool = false
var g_next_id  : int = 200      // ids for drag-created nodes (pins follow: in = id+1, out = id+2)
var g_next_link : int = 100
var g_drag_pin : int = 0        // source pin of a pin->empty drag (0 = none pending)
var g_drop_pos : float2         // canvas pos where the drag released

var NODE_TITLE : table<int; NarrativeState>   // per-id title slot (data-driven node idiom)

def seed() {
    // One source node with a single output pin to drag from.
    g_nodes[1] = Nd(id = 1, title = "Source", in_pin = 0, out_pin = 11, pos = float2(140.0, 230.0))
}

def commit_link(from_out : int; to_in : int) {
    let lid = g_next_link
    g_next_link ++
    g_links[lid] = Lk(id = lid, from_pin = from_out, to_pin = to_in)
}

def spawn_node(kind : string; pos : float2) : int {
    // Each drag-created node is a downstream sink: one input pin (id+1), one output (id+2).
    let nid = g_next_id
    g_next_id += 10
    g_nodes[nid] = Nd(id = nid, title = kind, in_pin = nid + 1, out_pin = nid + 2, pos = pos)
    imgui_node_editor::SetNodePosition(nid, pos)   // inside the editor block -> raw SetNodePosition
    return nid
}

def spawn_and_connect(kind : string) {
    let nid = spawn_node(kind, g_drop_pos)
    // Auto-connect: enqueue source -> new input. The link replays through begin_create's
    // query_new_link next frame (commit_link stores it) — never added to g_links directly.
    if (g_drag_pin != 0) {
        enqueue_new_link(g_ed, g_drag_pin, g_nodes[nid].in_pin)
        g_drag_pin = 0
    }
}

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        if (!g_seeded) {
            for (n in values(g_nodes)) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
            }
            g_seeded = true
        }
        for (n in values(g_nodes)) {
            node(n.id) {
                text(NODE_TITLE[n.id], (text = n.title))
                if (n.in_pin != 0) {
                    pin(n.in_pin, PinKind.Input) {
                        text("-> in")
                    }
                }
                if (n.out_pin != 0) {
                    pin(n.out_pin, PinKind.Output) {
                        text("out ->")
                    }
                }
            }
        }
        for (l in values(g_links)) {
            link(l.id, l.from_pin, l.to_pin)
        }
        // The create scope serves both gestures. Pins arrive output-first (a = output,
        // b = input) for a live pin->pin drag AND for the enqueue_new_link replay, so the
        // auto-link from a menu pick lands here too.
        var drag_fired = false
        begin_create(g_ed) {
            var a = 0
            var b = 0
            if (query_new_link(g_ed, a, b)) {
                if (a != 0 && b != 0 && a != b && accept_new_item(g_ed)) {
                    commit_link(a, b)
                }
            }
            if (show_new_node_drag(g_ed, g_drag_pin, g_drop_pos)) {
                drag_fired = true
            }
        }
        // The create-node menu is plain ImGui (screen space) -> Suspend/Resume island.
        with_suspended() {
            if (drag_fired) {
                open_popup("ne_create")
            }
            popup_window(CREATE_MENU, (str_id = "ne_create", flags = ImGuiWindowFlags.None)) {
                text("Create + connect")
                if (menu_label(ADD_MUL, (text = "Multiply"))) {
                    spawn_and_connect("Multiply")
                }
                if (menu_label(ADD_OUT, (text = "Output"))) {
                    spawn_and_connect("Output")
                }
            }
        }
    }
}

[export]
def init() {
    harness_init("Create by drag", 1000, 600)
    g_ed = create_node_editor()
    seed()
}

[export]
def update() {
    if (!harness_begin_frame()) return
    harness_new_frame()
    let io & = unsafe(GetIO())
    SetNextWindowPos(float2(0.0, 0.0), ImGuiCond.Always)
    SetNextWindowSize(io.DisplaySize, ImGuiCond.Always)
    let flags = (ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize |
                 ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoScrollbar |
                 ImGuiWindowFlags.NoScrollWithMouse | ImGuiWindowFlags.NoSavedSettings |
                 ImGuiWindowFlags.NoBringToFrontOnFocus)
    window(MAIN_WIN, (text = "Create by drag", closable = false, flags = flags)) {
        draw_editor()
    }
    harness_end_frame()
}

[export]
def shutdown() {
    destroy_node_editor(g_ed)
    harness_shutdown()
}

[export]
def main() {
    init()
    while (!exit_requested()) {
        update()
    }
    shutdown()
}
