options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record clipboard.apng - click a node and Ctrl+D to duplicate, then click
//! another and Ctrl+C / Ctrl+V to copy + paste. Voiced and self-verifying: each click
//! MUST select its node, Ctrl+D MUST spawn the duplicate, and Ctrl+V MUST spawn the
//! pasted node (Ctrl+C is verified transitively through the paste), or the recording
//! aborts at teardown. The keycap + modifier HUD (imgui_key_hud) is on, and each chord
//! fires partway INTO its voice line so the keycap + Ctrl pill pop while it is named.
//! Shortcuts are Ctrl on every platform; the click focuses the canvas the gate needs.
//! The headless regression is test_clipboard_tutorial.das.

let CANVAS = "MAIN_WIN/graph"

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // The node's title row - clicking it selects the node AND focuses the canvas (the gate
    // the Ctrl shortcuts need); the center would hit the output pin.
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f, (b?["y"] ?? 0.0f) + 10.0f)
}

def click_node(app : ImguiApp; pt : tuple<float; float>) {
    var ev : array<JsonValue?>
    ev |> click_at(0, pt, 250, 0)
    post_command(app, "imgui_mouse_play", JV((events = ev)))
    wait_for_mouse_idle(app)
}

def chord_under_voice(app : ImguiApp; dwell : uint; key : string) {
    // Fire the Ctrl chord partway into the already-posted voice line, so the keycap + Ctrl
    // pill pop while the line names it, then hold out the rest of the dwell.
    let lead = dwell > 1200u ? 700u : dwell / 3u
    hold_content(app, lead)
    post_command(app, "imgui_key_chord", JV((mods = ["Ctrl"], key = key)))
    wait_for_key_idle(app, 4.0f)
    hold_content(app, dwell > lead ? dwell - lead : 0u)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/clipboard.das",
                                   "clipboard.apng", 60) $(app) {
        let T_A = "{CANVAS}/node_1"
        let T_B = "{CANVAS}/node_2"
        let T_DUP = "{CANVAS}/node_200"
        let T_PASTE = "{CANVAS}/node_210"

        var snap = wait_for_widget(app, T_A, 15.0f)
        if (snap == null) {
            panic("{T_A} never rendered - wrong app running?")
        }
        // Keyboard helper: the bottom-center keycap + modifier strip, so the Ctrl chords
        // are visible on screen as they fire (this tutorial is all about Ctrl+D/C/V). Bump
        // the keycap linger to 2.5s so [Ctrl][D] stays readable through its voice line.
        post_command(app, "imgui_key_hud", JV((enabled = true, show_modifiers = true, keycap_fade_s = 2.5f)))

        let pA = title_point(snap, T_A)
        let pB = title_point(snap, T_B)

        // ---- Beat 1: click A -> select + focus the canvas ----
        move_to(app, pA, 600)
        wait_for_mouse_idle(app)
        click_node(app, pA)
        record_check_value(app, T_A, "selected", true)
        say(app, "click a node to select it", T_A,
            [voice = "Click a node to select it - the click also focuses the canvas, which the edit shortcuts need."])

        // ---- Beat 2: Ctrl+D -> duplicate (chord pops under the voice) ----
        chord_under_voice(app, say_begin(app, "Ctrl+D duplicates", T_DUP,
            [voice = "Ctrl+D duplicates the selection - accept_duplicate fires and the app clones it next to the original."]), "D")
        record_check_rendered(app, T_DUP, true)

        // ---- Beat 3: click B -> select ----
        move_to(app, pB, 600)
        wait_for_mouse_idle(app)
        click_node(app, pB)
        record_check_value(app, T_B, "selected", true)
        say(app, "select another node", T_B,
            [voice = "Now select a different node to copy."])

        // ---- Beat 4: Ctrl+C -> copy (internal; proven by the paste below) ----
        chord_under_voice(app, say_begin(app, "Ctrl+C copies", T_B,
            [voice = "Ctrl+C copies it - the editor only reports the chord; the app serializes the selection into its own clipboard."]), "C")

        // ---- Beat 5: Ctrl+V -> paste ----
        chord_under_voice(app, say_begin(app, "Ctrl+V pastes", T_PASTE,
            [voice = "Ctrl+V pastes - accept_paste fires and the app recreates the copied node from its clipboard."]), "V")
        record_check_rendered(app, T_PASTE, true)
    }
}
