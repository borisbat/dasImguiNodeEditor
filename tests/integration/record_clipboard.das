options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record clipboard.apng — click a node and Ctrl+D to duplicate it, then click
//! another and Ctrl+C / Ctrl+V to copy + paste. Narrated, with synthetic clicks + real
//! Ctrl chords. Run with `daslang tests/integration/record_clipboard.das`, then ffmpeg
//! the .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO fully to the synthetic timeline — without it the
//! real OS cursor races the synth and the canvas never gains focus, so the editor's
//! shortcut gate (IsFocused) stays shut and the chords no-op. Shortcuts are Ctrl on every
//! platform. The headless regression is test_clipboard_tutorial.das.

let CANVAS = "MAIN_WIN/graph"

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // The node's title row (top edge) — clicking it selects the node AND focuses the canvas.
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f, (b?["y"] ?? 0.0f) + 10.0f)
}

def click_node(app : ImguiApp; pt : tuple<float; float>) {
    var ev : array<JsonValue?>
    ev |> click_at(0, pt, 250, 0)
    post_command(app, "imgui_mouse_play", JV((events = ev)))
    wait_for_mouse_idle(app)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/clipboard.das",
                                   "clipboard.apng", 55) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_1", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_1 never rendered — wrong app running?")
        }
        // Synthetic IO only — no real-cursor race (see header note).
        post_command(app, "set_user_control", JV((enabled = false)))

        let pA = title_point(snap, "{CANVAS}/node_1")
        let pB = title_point(snap, "{CANVAS}/node_2")

        // ---- duplicate A ----
        move_to(app, pA, 600)
        wait_for_mouse_idle(app)
        say(app, "Click a node to select it - this also focuses the canvas.", "{CANVAS}/node_1")
        click_node(app, pA)
        say(app, "Ctrl+D duplicates the selection - accept_duplicate fires; the app clones it.", "{CANVAS}/node_1")
        post_command(app, "imgui_key_chord", JV((mods = ["Ctrl"], key = "D")))
        wait_for_key_idle(app, 4.0f)
        var dupSnap = wait_for_widget(app, "{CANVAS}/node_200", 6.0f)
        print("duplicate -> {dupSnap != null}\n")

        // ---- copy + paste B ----
        move_to(app, pB, 600)
        wait_for_mouse_idle(app)
        say(app, "Select another node, then Ctrl+C to copy.", "{CANVAS}/node_2")
        click_node(app, pB)
        post_command(app, "imgui_key_chord", JV((mods = ["Ctrl"], key = "C")))
        wait_for_key_idle(app, 4.0f)
        say(app, "Ctrl+V pastes it - accept_paste fires; the app recreates the copied node.", "{CANVAS}/node_2")
        post_command(app, "imgui_key_chord", JV((mods = ["Ctrl"], key = "V")))
        wait_for_key_idle(app, 4.0f)
        var pasteSnap = wait_for_widget(app, "{CANVAS}/node_210", 6.0f)
        print("paste -> {pasteSnap != null}\n")
        if (pasteSnap != null) {
            say(app, "The app owns the clipboard - the editor only reports the chord through accept_copy / accept_paste.", "{CANVAS}/node_210")
        } else {
            say(app, "(the paste did not land - see test_clipboard_tutorial for the sequence)", "{CANVAS}/node_2")
        }
    }
}
