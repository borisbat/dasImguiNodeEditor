options gen2
options _comment_hygiene = true

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: connect_by_drag — the signature node-editor gesture. Drag from an
// output pin to an input pin and a link is created.
//
//   begin_create(ed) {                    -- open the create-interaction scope
//       if (query_new_link(ed, a, b)) {   -- a pin-drag is hovering a target pin
//           if (accept_new_item(ed)) {    -- the user released: commit the link
//               ... add the link ...
//           }
//       }
//   }
//
// The model here is intentionally trivial — one output pin, one input pin, and a
// single bool tracking whether they are joined. A real graph would validate kinds,
// dedupe, and store a list; this just teaches the gesture and the create scope.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/connect_by_drag.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/connect_by_drag.das
// =============================================================================

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false
var g_connected : bool = false

let OUT_PIN = 11
let IN_PIN  = 21
let LINK_ID = 100

[export]
def init() {
    harness_init("Connect by drag", 1000, 600)
    g_ed = create_node_editor()
}

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        // Seed two nodes side by side, once.
        if (!g_seeded) {
            imgui_node_editor::SetNodePosition(1, float2(120.0, 160.0))
            imgui_node_editor::SetNodePosition(2, float2(560.0, 160.0))
            g_seeded = true
        }
        node(1) {
            text("Source")
            pin(OUT_PIN, PinKind.Output) {
                text("value ->")
            }
        }
        node(2) {
            text("Sink")
            pin(IN_PIN, PinKind.Input) {
                text("-> value")
            }
        }
        // The one link, drawn once it has been made.
        if (g_connected) {
            link(LINK_ID, OUT_PIN, IN_PIN)
        }
        // The hero gesture: a pin-drag released on a compatible pin commits a link.
        // With exactly one output + one input, any cross-pin drag IS the connection.
        begin_create(g_ed) {
            var a = 0
            var b = 0
            if (query_new_link(g_ed, a, b)) {
                if (a != 0 && b != 0 && a != b && accept_new_item(g_ed)) {
                    g_connected = true
                }
            }
        }
    }
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
    window(MAIN_WIN, (text = "Connect by drag", closable = false, flags = flags)) {
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
