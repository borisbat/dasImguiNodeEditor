options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record delete_and_select.apng — select the middle node, press Delete, and
//! watch the node plus the two links on its pins cascade away. Narrated, with a
//! synthetic left-click to select then a synthetic Delete key. Run with
//! `daslang tests/integration/record_delete_and_select.das`, then ffmpeg the .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO fully to the synthetic timeline — without it
//! the real OS cursor races the synth and the canvas never gains hover, so the Delete
//! key's CanAcceptUserInput gate stays shut. The editor's native Delete key raises the
//! selection through begin_delete — the same path delete_and_select.das handles. The
//! title row selects the node (its center hits a pin, which eats the click).

let CANVAS = "MAIN_WIN/graph"

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // The node's title row (top edge) — clicking the center hits a pin item, which
    // eats the click; the title row reliably selects the node.
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f, (b?["y"] ?? 0.0f) + 10.0f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/delete_and_select.das",
                                   "delete_and_select.apng", 45) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_2", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_2 never rendered — wrong app running?")
        }
        // Synthetic IO only — no real-cursor race (see header note).
        post_command(app, "set_user_control", JV((enabled = false)))

        let sel_pt = title_point(snap, "{CANVAS}/node_2")

        say(app, "A -> B -> C: one chain, two links. We will delete the middle node, B.", "{CANVAS}/node_2")

        // Select B (title-row click). wait_for_mouse_idle lets the click fully drain
        // before we poll the selection (the snapshot-during-recording lesson from #2).
        move_to(app, sel_pt, 700)
        wait_for_mouse_idle(app)
        say(app, "Click a node to select it - the editor highlights the selection.", "{CANVAS}/node_2")
        var ev : array<JsonValue?>
        ev |> click_at(0, sel_pt, 250, 0)
        post_command(app, "imgui_mouse_play", JV((events = ev)))
        wait_for_mouse_idle(app)
        var selSnap = wait_until_sec(app, 6.0f) $(var sn) {
            return find_widget(sn, "{CANVAS}/node_2")?["payload"]?["selected"] ?? false
        }
        print("SELECT node_2 -> {selSnap != null}\n")

        // Press Delete: the editor raises the selection through begin_delete, where the
        // app accepts it and cascades the dangling links.
        say(app, "Press Delete - the editor raises the selection through begin_delete; the app accepts it.", "{CANVAS}/node_2")
        let del = int(ImGuiKey.Delete)
        post_command(app, "imgui_key_press",   JV((key = del)))
        post_command(app, "imgui_key_release", JV((key = del)))

        // Gate: B is gone AND both its links cascaded out.
        var goneSnap = wait_until_sec(app, 8.0f) $(var sn) {
            return !widget_exists(sn, "{CANVAS}/node_2")
        }
        let node_gone = goneSnap != null
        let links_gone = (node_gone &&
            !widget_exists(goneSnap, "{CANVAS}/link_100") &&
            !widget_exists(goneSnap, "{CANVAS}/link_101"))
        print("DELETE node_2 gone -> {node_gone}, links cascaded -> {links_gone}\n")

        if (links_gone) {
            say(app, "accept_deleted_node removed B; the two links on its pins cascaded away. A and C remain, disconnected.", "{CANVAS}/node_1")
        } else {
            say(app, "(the delete did not land - check the selection / Delete key)", "{CANVAS}/node_2")
        }
    }
}
