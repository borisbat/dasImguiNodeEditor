options gen2

// Driven fixture for the [widget]/[container] forward_argument CALL FORMS. Every
// node-editor entity is rendered BOTH ways so tests/integration/test_call_forms.das
// can assert the tuple and non-tuple/auto-fill paths produce identical snapshot
// entries (same path key, same payload):
//   node_editor : `size` OMITTED        -> container auto-fill (default float2(0,0))
//   node        : node(1) {…}           (non-tuple, color auto-fills sentinel)
//                 node(2, (color=…)) {…} (tuple)
//   pin         : pin(11, PinKind.Output) (positional kind)
//                 pin(21, (kind=…))       (tuple)
//   link        : link(100, 11, 21)        (positional)
//                 link(101, (from=…, to=…))(tuple)
// Not a user example — a test app, kept static (no create/delete handlers).

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false

[export]
def init() {
    harness_init("Call Forms", 1280, 720)
    g_ed = create_node_editor()
}

def draw_editor() {
    // `size` omitted on purpose — exercises the [container] tuple auto-fill.
    node_editor("forms", (editor = g_ed)) {
        // Seed positions ONCE (raw SetNodePosition — the editor is already current
        // inside the block, so do NOT use the SetCurrentEditor-bracketed wrapper).
        if (!g_seeded) {
            imgui_node_editor::SetNodePosition(1, float2(40.0, 40.0))
            imgui_node_editor::SetNodePosition(2, float2(340.0, 40.0))
            imgui_node_editor::SetNodePosition(3, float2(640.0, 40.0))
            g_seeded = true
        }
        node(1) {                                       // node: non-tuple
            pin(11, PinKind.Output) {                   // pin: positional kind
                text("out ->")
            }
        }
        node(2, (color = float4(0.30, 0.12, 0.12, 0.80))) {   // node: tuple
            pin(21, (kind = PinKind.Input)) {           // pin: tuple form
                text("-> in")
            }
            pin(22, PinKind.Output) {
                text("out ->")
            }
        }
        node(3) {                                       // node: non-tuple
            pin(31, (kind = PinKind.Input)) {
                text("-> in")
            }
        }
        link(100, 11, 21)                               // link: positional
        link(101, (from = 22, to = 31))                 // link: tuple
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
    window(MAIN_WIN, (text = "Call Forms", closable = false, flags = flags)) {
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
