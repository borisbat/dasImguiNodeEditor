options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record navigation.apng — the three view ops, each fired by a real synthetic
//! click on its toolbar button: Fit All (NavigateToContent), Frame Selection
//! (navigate_to_selection), Center #1 (center_node_on_screen). The recording narrates each
//! and lets the view settle between clicks. Run with
//! `daslang tests/integration/record_navigation.das`, then ffmpeg the .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO to the synthetic timeline — without it the real OS
//! cursor races the synth and the button clicks are eaten. The headless regression is
//! test_navigation.das.

let CANVAS = "MAIN_WIN/graph"

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/navigation.das",
                                   "navigation.apng", 50) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_3", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_3 never rendered — wrong app running?")
        }
        post_command(app, "set_user_control", JV((enabled = false)))

        say(app, "The graph is spread wide — node 3 sits far to the bottom-right.", "{CANVAS}/node_3")
        wait_for_mouse_idle(app)

        say(app, "Fit All → NavigateToContent zooms out so the whole graph fits.", "MAIN_WIN/FIT_ALL")
        click(app, "MAIN_WIN/FIT_ALL")
        wait_for_mouse_idle(app)

        say(app, "Frame Selection → navigate_to_selection frames just the selected nodes.", "MAIN_WIN/FRAME_SEL")
        click(app, "MAIN_WIN/FRAME_SEL")
        wait_for_mouse_idle(app)

        say(app, "Center #1 → center_node_on_screen pans node 1 to the middle.", "MAIN_WIN/CENTER_FIRST")
        click(app, "MAIN_WIN/CENTER_FIRST")
        wait_for_mouse_idle(app)
        say(app, "Each op moves the VIEW only — no node's canvas position changed.", "{CANVAS}/node_1")
        wait_for_mouse_idle(app)
    }
}
