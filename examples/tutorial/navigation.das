options gen2
options _comment_hygiene = true

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: navigation — the view ops, and the one that fools you.
//
//   NavigateToContent(duration)            -- fit the whole graph to the viewport (VIEW)
//   navigate_to_selection(ed, zoomIn, dur) -- frame just the selected nodes        (VIEW)
//   center_node_on_screen(ed, nodeId)      -- MOVES the node to the view center    (GRAPH!)
//
// The editor separates the GRAPH (node positions, in canvas space) from the VIEW
// (the pan + zoom that maps canvas to screen). Fit All and Frame Selection change only
// the view — no node moves. center_node_on_screen is the footgun: despite the name,
// upstream CenterNodeOnScreen MOVES the node to the view center, it does not pan.
// Placement also matters: NavigateToContent must run INSIDE the node_editor block with
// the editor current, so the app raises a flag and services it there;
// navigate_to_selection / center_node_on_screen are bracketed wrappers that set the
// editor current themselves, so the toolbar buttons call them directly.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/navigation.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/navigation.das
// =============================================================================

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false
var g_fit : bool = false   // "Fit All" raises this; serviced inside the editor block

// Spread wide so a fit visibly zooms out and recenters.
struct Nd {
    id  : int
    pos : float2
}
let NODES = [
    Nd(id = 1, pos = float2(40.0,   40.0)),
    Nd(id = 2, pos = float2(560.0,  300.0)),
    Nd(id = 3, pos = float2(1180.0, 560.0))
]

def toolbar() {
    if (button(FIT_ALL, (text = "Fit All"))) {
        g_fit = true   // NavigateToContent runs inside the block (editor must be current)
    }
    same_line()
    if (button(FRAME_SEL, (text = "Frame Selection"))) {
        navigate_to_selection(g_ed, false, -1.0)   // bracketed wrapper → safe outside the block
    }
    same_line()
    if (button(CENTER_FIRST, (text = "Center #1"))) {
        center_node_on_screen(g_ed, 1)   // NB: MOVES node 1 to the view center - not a view op
    }
}

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        if (!g_seeded) {
            for (n in NODES) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
            }
            g_seeded = true
        }
        for (n in NODES) {
            node(n.id) {
                text("Node {n.id}")
                pin(n.id * 10 + 1, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) {
                    text("out ->")
                }
            }
        }
        // Service "Fit All" here, with the editor current. NavigateToContent(0) snaps
        // instantly; pass a duration (seconds) for an animated fly-to instead.
        if (g_fit) {
            imgui_node_editor::NavigateToContent(0.0)
            g_fit = false
        }
    }
}

[export]
def init() {
    harness_init("Navigation", 1000, 600)
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
    window(MAIN_WIN, (text = "Navigation", closable = false, flags = flags)) {
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

[export]
def main() {
    init()
    while (!exit_requested()) {
        update()
    }
    shutdown()
}
