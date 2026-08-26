options gen2
options _comment_hygiene = true

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: groups — a comment box that corrals the nodes dragged onto it.
//
//   node_group(id, (size = float2(w, h))) {     -- a pin-less node; its body is the label
//       text(...)
//   }
//   group_hint(id) $(var fg; var bg) {           -- off-screen label when zoomed out
//       fg |> add_text(GetGroupMin(), color, title)
//   }
//
// A GROUP is just a node with no pins and an explicit content `size`. Drag nodes
// over it and they move WITH the group — the editor handles that for free. Draw
// groups FIRST so regular nodes paint on top of them. The group is editor-owned
// geometry after its first frame, exactly like a node position: seed `size` once,
// then `set_group_size` to resize it later (mutating your own struct won't).
//
// group_hint draws a floating label when the canvas is zoomed out far enough that
// the group's own title is too small to read; it self-gates (a no-op at normal
// zoom), so the loop is unconditional.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/groups.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/groups.das
// =============================================================================

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false

// node_group(id) and node(id) live in the SAME id space — keep them disjoint.
let GROUP_ID = 1
let NODE_A   = 10
let NODE_B   = 20

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        if (!g_seeded) {
            imgui_node_editor::SetNodePosition(GROUP_ID, float2(60.0, 80.0))
            imgui_node_editor::SetNodePosition(NODE_A, float2(130.0, 170.0))   // INSIDE the group
            imgui_node_editor::SetNodePosition(NODE_B, float2(560.0, 200.0))   // OUTSIDE the group
            g_seeded = true
        }
        // The group, drawn first so the two nodes sit on top of it. `size` is the
        // INITIAL content box — once placed, the editor owns it.
        node_group(GROUP_ID, (size = float2(300.0, 280.0))) {
            text(GROUP_TITLE, (text = "Inputs"))
        }
        // Zoomed-out label: floats the title above the group bounds in the hint draw
        // list. GetGroupMin is the group's top-left (screen space inside a hint). The
        // hint lists swap R/B for asymmetric colors, so a near-grey label is safest.
        group_hint(GROUP_ID) $(var fg; var _bg) {
            let mn = imgui_node_editor::GetGroupMin()
            fg |> add_text(float2(mn.x + 4.0, mn.y - 18.0), rgba(232u, 226u, 210u, 255u), "Inputs")
        }
        // Two ordinary nodes: Texture starts INSIDE the group, Tint OUTSIDE. Membership is
        // spatial - dragging the group carries whatever sits within its bounds at that moment
        // (the editor's FindNodesInRect), so drag Tint in and it joins, drag it out and it leaves.
        node(NODE_A) {
            text("Texture")
            pin(11, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) {
                text("RGBA ->")
            }
        }
        node(NODE_B) {
            text("Tint")
            pin(21, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) {
                text("Color ->")
            }
        }
    }
}

[export]
def init() {
    harness_init("Groups", 1000, 600)
    g_ed = create_node_editor()
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
    window(MAIN_WIN, (text = "Groups", closable = false, flags = flags)) {
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
