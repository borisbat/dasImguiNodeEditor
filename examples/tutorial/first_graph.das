options gen2

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: first_graph — the four constructs of a node-editor canvas.
//
//   create_node_editor()            -- an EditorContext owns the canvas state
//                                      (pan / zoom / selection). Destroy it at
//                                      shutdown.
//   node_editor("name", (editor=))  -- the canvas container; everything inside
//                                      is drawn in canvas space.
//   node(id) { ... }                -- a box. Its body is plain ImGui widgets.
//   pin(id, PinKind.Output/Input)   -- a connection point on a node.
//   link(id, from_pin, to_pin)      -- an edge joining an output pin to an input.
//
// The model is ID-ONLY: nodes, pins and links are just integer ids you choose.
// The editor tracks geometry and interaction; YOU own what the ids mean. This
// graph is static — see connect_by_drag for making links with the mouse.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/first_graph.das
// LIVE:       daslang-live modules/dasImgui/examples/tutorial/first_graph.das
// =============================================================================

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false

[export]
def init() {
    harness_init("First graph", 1000, 600)
    g_ed = create_node_editor()
}

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        // Lay the two nodes out once; after this the user (or the editor) owns
        // their positions.
        if (!g_seeded) {
            imgui_node_editor::SetNodePosition(1, float2(120.0, 180.0))
            imgui_node_editor::SetNodePosition(2, float2(560.0, 180.0))
            g_seeded = true
        }
        node(1) {
            text("Input")
            pin(11, PinKind.Output) {
                text("value ->")
            }
        }
        node(2) {
            text("Output")
            pin(21, PinKind.Input) {
                text("-> value")
            }
        }
        // One edge: node 1's output pin (11) feeds node 2's input pin (21).
        link(100, 11, 21)
    }
}

[export]
def update() {
    if (!harness_begin_frame()) return
    harness_apply_synth_io()   // drain the recording driver's move_to / cursor synth
    harness_new_frame()
    let io & = unsafe(GetIO())
    SetNextWindowPos(float2(0.0, 0.0), ImGuiCond.Always)
    SetNextWindowSize(io.DisplaySize, ImGuiCond.Always)
    let flags = (ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize |
                 ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoScrollbar |
                 ImGuiWindowFlags.NoScrollWithMouse | ImGuiWindowFlags.NoSavedSettings |
                 ImGuiWindowFlags.NoBringToFrontOnFocus)
    window(MAIN_WIN, (text = "First graph", closable = false, flags = flags)) {
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
