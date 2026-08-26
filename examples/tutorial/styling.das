options gen2
options _comment_hygiene = true

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live
require imgui/imgui_node_editor_theme_daslang

// =============================================================================
// TUTORIAL: styling — make nodes look the way you want.
//
//   apply_daslang_node_editor_style(ed)        -- canvas theme (warm-dark + amber)
//   node(id, (color = float4(r,g,b,a)))        -- per-node background tint
//   pin(id, (kind=, pivot_alignment=))         -- where the link attaches on the pin
//   with_style_var(StyleVar.NodeRounding, 10)  -- scoped style VAR around a node
//   with_style_color(StyleColor.NodeBorder, c) -- scoped style COLOR (composes with the var)
//   with_node_background_drawlist(id) $(var dl) -- raw drawing behind a node
//
// first_graph drew bare boxes. The editor's look is layered: a canvas-wide THEME,
// per-node TINTS (the `color` arg), SCOPED style var/color brackets for one-off
// nodes, pin PIVOTS that move the link-attach point onto the node edge, and a
// background DRAW LIST for custom art. Each layer is independent — reach for the
// smallest one that does the job.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/styling.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/styling.das
// =============================================================================

var g_ed : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        if (!g_seeded) {
            imgui_node_editor::SetNodePosition(1, float2(80.0, 80.0))
            imgui_node_editor::SetNodePosition(2, float2(360.0, 120.0))
            imgui_node_editor::SetNodePosition(3, float2(660.0, 160.0))
            g_seeded = true
        }
        // (1) A plain tint: the `color` arg fills the node background. Green for a source.
        node(1, (color = float4(0.15, 0.35, 0.18, 0.78))) {
            text("Source")
            pin(12, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) {
                text("out ->")
            }
        }
        // (2) Default look — no tint, square corners, default border. Inputs pivot on the
        // left edge (x = 0), outputs on the right (x = 1); with no pivot the link springs
        // from the pin label's center. Pin ids are unique editor-wide — same ids merge.
        node(2) {
            text("Passthrough")
            pin(21, (kind = PinKind.Input, pivot_alignment = float2(0.0, 0.5))) {
                text("-> in")
            }
            pin(22, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) {
                text("out ->")
            }
        }
        // (3) The showcase node: a red tint, PLUS scoped style brackets — rounded
        // corners (a style VAR) and an amber border (a style COLOR). The two wrappers
        // compose; each restores its previous value when the block ends.
        with_style_var(imgui_node_editor::StyleVar.NodeRounding, 10.0) {
            with_style_color(imgui_node_editor::StyleColor.NodeBorder, float4(0.910, 0.631, 0.227, 1.0)) {
                node(3, (color = float4(0.40, 0.18, 0.18, 0.78))) {
                    text("Output")
                    pin(31, (kind = PinKind.Input, pivot_alignment = float2(0.0, 0.5))) {
                        text("-> in")
                    }
                }
            }
        }
        // A custom accent stripe down node 3's left edge. The node's draw channels only
        // exist once it is fully built, so this runs AFTER the node block, reading the
        // editor-owned geometry back (GetNodePosition / GetNodeSize).
        with_node_background_drawlist(3) $(var dl) {
            let p = imgui_node_editor::GetNodePosition(3)
            let s = imgui_node_editor::GetNodeSize(3)
            dl |> add_rect_filled(p, float2(p.x + 5.0, p.y + s.y), rgba(255u, 90u, 90u, 220u))
        }
        link(100, 12, 31)
    }
}

[export]
def init() {
    harness_init("Styling", 1000, 600)
    g_ed = create_node_editor()
    apply_daslang_node_editor_style(g_ed)   // warm-dark canvas + amber grid to match daslang's ImGui theme
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
    window(MAIN_WIN, (text = "Styling", closable = false, flags = flags)) {
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
