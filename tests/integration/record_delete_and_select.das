options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record delete_and_select.apng - select the middle node of an A -> B -> C
//! chain, press Delete, and watch B plus the two links on its pins cascade away. Voiced
//! and self-verifying: the click MUST select B, and the Delete MUST remove B and both
//! its links, or the recording aborts at teardown. Pulses the chain first to show it is
//! live before it is cut, and the imgui_key_hud pops a [Del] keycap as the key fires. The
//! headless regression for the same gesture is test_delete_and_select.das.

let CANVAS = "MAIN_WIN/graph"

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // The node's title row (top edge) - clicking the center hits a pin item, which
    // eats the click; the title row reliably selects the node.
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f, (b?["y"] ?? 0.0f) + 10.0f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/delete_and_select.das",
                                   "delete_and_select.apng", 55) $(app) {
        let T_B = "{CANVAS}/node_2"
        let T_L100 = "{CANVAS}/link_100"
        let T_L101 = "{CANVAS}/link_101"

        let s = ne_open(app, CANVAS)
        if (s.handle == uint64(0)) {
            panic("{CANVAS} never rendered / no editor handle - wrong app running?")
        }
        var snap = wait_for_widget(app, T_B, 15.0f)
        if (snap == null) {
            panic("{T_B} never rendered - wrong app running?")
        }
        let sel_pt = title_point(snap, T_B)

        // Keyboard helper: pop a [Del] keycap bottom-center when the key fires (no modifiers
        // - Delete is a plain key, not a chord); keycap_fade_s lingers it through the voice.
        post_command(app, "imgui_key_hud", JV((enabled = true, show_modifiers = false, keycap_fade_s = 2.5f)))

        // ---- Beat 1: the chain ----
        record_check_rendered(app, T_B, true)
        say(app, "A -> B -> C: two links", T_B,
            [voice = "Here is a tiny chain - node A to B to C, joined by two links."])

        // ---- Beat 2: show it is live (pulse both links) ----
        let dwell = say_begin(app, "the chain is live", T_B,
            [voice = "Both links carry data end to end - we can pulse them to see the chain is live before we cut it."])
        var pulses = int(dwell) / 500
        if (pulses < 4) { pulses = 4 }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            ne_flow(s, 101)
            sleep(interval)
        }

        // ---- Beat 3: select B (title-row click) ----
        move_to(app, sel_pt, 700)
        wait_for_mouse_idle(app)
        var ev : array<JsonValue?>
        ev |> click_at(0, sel_pt, 250, 0)
        post_command(app, "imgui_mouse_play", JV((events = ev)))
        wait_for_mouse_idle(app)
        // Hard self-verify: the click MUST select B.
        record_check_value(app, T_B, "selected", true)
        say(app, "click B to select it", T_B,
            [voice = "Click a node to select it - the editor highlights the selection for you."])

        // ---- Beat 4: Delete -> B and both its links cascade ----
        // Fire Delete partway into the voice so the [Del] keycap pops as the line names it.
        let del = int(ImGuiKey.Delete)
        let dwell2 = say_begin(app, "Delete -> B + both links cascade", "{CANVAS}/node_1",
            [voice = "Press Delete and the editor raises B through begin_delete; accepting it drops B and cascades the two links on its pins. A and C remain, disconnected."])
        let lead = dwell2 > 1200u ? 700u : dwell2 / 3u
        sleep(lead)
        post_command(app, "imgui_key_press", JV((key = del)))
        post_command(app, "imgui_key_release", JV((key = del)))
        // Hard self-verify: B is gone AND both links cascaded out, or abort at teardown.
        record_check_rendered(app, T_B, false)
        record_check_rendered(app, T_L100, false)
        record_check_rendered(app, T_L101, false)
        sleep(dwell2 > lead ? dwell2 - lead : 0u)
    }
}
