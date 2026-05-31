options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record styling.apng — a static tour of the styling layers. There is no
//! interaction to drive; the recording just narrates the three styled nodes (tinted
//! source, default passthrough, rounded + amber-bordered output with an accent stripe)
//! while the synthetic cursor points at each. Run with
//! `daslang tests/integration/record_styling.das`, then ffmpeg the .apng to .mp4.

let CANVAS = "MAIN_WIN/graph"

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/styling.das",
                                   "styling.apng", 50) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_3", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_3 never rendered — wrong app running?")
        }
        post_command(app, "set_user_control", JV((enabled = false)))

        say(app, "node(id, color=...) tints a node's background - green for this source.", "{CANVAS}/node_1")
        wait_for_mouse_idle(app)
        say(app, "No tint, square corners: the editor's default node look.", "{CANVAS}/node_2")
        wait_for_mouse_idle(app)
        say(app, "with_style_var (rounding) + with_style_color (amber border) compose around this output node.", "{CANVAS}/node_3")
        wait_for_mouse_idle(app)
        say(app, "The red accent stripe is custom art on the node's background draw list.", "{CANVAS}/node_3")
        wait_for_mouse_idle(app)
    }
}
