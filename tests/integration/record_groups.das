options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record groups.apng — a group/comment box with two nodes seeded on top of it,
//! then a drag of the GROUP that carries both nodes with it (the editor's group-move). The
//! recording narrates the box and demonstrates the corral behavior with a slow synthetic
//! drag on the group's title bar. Run with `daslang tests/integration/record_groups.das`,
//! then ffmpeg the .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO to the synthetic timeline — without it the real OS
//! cursor races the synth and the drag is eaten. The headless regression is test_groups.das.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/groups.das",
                                   "groups.apng", 50) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_group_1", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_group_1 never rendered — wrong app running?")
        }
        post_command(app, "set_user_control", JV((enabled = false)))

        say(app, "node_group(id, size=...) is a pin-less node — a comment box that corrals what's on it.", "{CANVAS}/node_group_1")
        wait_for_mouse_idle(app)
        say(app, "Two ordinary nodes seeded inside the box.", "{CANVAS}/node_10")
        wait_for_mouse_idle(app)

        // Drag the group by its title strip (just inside the top edge). The two nodes
        // move with it — the editor handles the corral for free.
        let g_top = widget_center(snap, "{CANVAS}/node_group_1")
        let grab : tuple<float; float> = (g_top._0, g_top._1 - 120.0)   // up near the title bar
        let dest : tuple<float; float> = (grab._0 + 220.0, grab._1 + 60.0)
        say(app, "Drag the group's title bar — the nodes on it come along.", "{CANVAS}/node_group_1")
        var events <- [
            JV((t_ms = 0,    kind = "move",   x = grab._0, y = grab._1)),
            JV((t_ms = 300,  kind = "move",   x = grab._0, y = grab._1)),
            JV((t_ms = 380,  kind = "button", button = 0,  action = "press")),
            JV((t_ms = 500,  kind = "move",   x = grab._0, y = grab._1)),
            JV((t_ms = 1400, kind = "move",   x = dest._0, y = dest._1)),
            JV((t_ms = 1550, kind = "move",   x = dest._0, y = dest._1)),
            JV((t_ms = 1650, kind = "button", button = 0,  action = "release")),
            JV((t_ms = 1800, kind = "move",   x = dest._0, y = dest._1))
        ]
        post_command(app, "imgui_mouse_play", JV((events = events)))
        wait_for_mouse_idle(app)
        say(app, "The whole group moved together.", "{CANVAS}/node_group_1")
        wait_for_mouse_idle(app)
    }
}
