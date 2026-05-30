options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record context_menus.apng — right-click a node for its "Delete node" menu
//! (delete it, link cascades), then right-click the empty canvas for the background
//! "Add a node" menu (create one at the cursor). Narrated, synthetic right-clicks.
//! Run with `daslang tests/integration/record_context_menus.das`, then ffmpeg the
//! .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO fully to the synthetic timeline — without it
//! the real OS cursor races the synth and consumes the menu clicks (a popup-close
//! swallows the next right-click). The right-click must hit the node BODY (its center);
//! a click on a pin opens the pin menu instead.

let CANVAS = "MAIN_WIN/graph"

def center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

def right_click(app : ImguiApp; pt : tuple<float; float>) {
    var ev : array<JsonValue?>
    ev |> click_at(0, pt, 250, 1)   // button 1 = right
    post_command(app, "imgui_mouse_play", JV((events = ev)))
    wait_for_mouse_idle(app)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/context_menus.das",
                                   "context_menus.apng", 55) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_1", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_1 never rendered — wrong app running?")
        }
        // Synthetic IO only — no real-cursor race (see header note).
        post_command(app, "set_user_control", JV((enabled = false)))

        let del_item = "{CANVAS}/NODE_MENU/DEL_ITEM"
        let add_item = "{CANVAS}/BG_MENU/ADD_ITEM"
        let new_node = "{CANVAS}/node_200"
        let cA = center(snap, "{CANVAS}/node_1")
        let bg_pt : tuple<float; float> = (720.0, 430.0)   // empty canvas

        // ---- node menu: right-click node A's body ----
        say(app, "Right-click a node for its own context menu.", "{CANVAS}/node_1")
        move_to(app, cA, 700)
        wait_for_mouse_idle(app)
        right_click(app, cA)
        var nodeMenuSnap = wait_for_widget(app, del_item, 6.0f)
        print("node menu opened -> {nodeMenuSnap != null}\n")
        say(app, "show_node_context_menu reports which node was hit; 'Delete node' enqueues it.", del_item)
        click(app, del_item)
        var goneSnap = wait_until_sec(app, 6.0f) $(var sn) {
            return !widget_exists(sn, "{CANVAS}/node_1")
        }
        print("node A deleted via node menu -> {goneSnap != null}\n")
        say(app, "Deleted through begin_delete - the link on its pin cascaded away too.", "{CANVAS}/node_2")

        // ---- background menu: right-click empty canvas ----
        say(app, "Right-click empty canvas for the background menu.", "{CANVAS}/node_2")
        move_to(app, bg_pt, 700)
        wait_for_mouse_idle(app)
        right_click(app, bg_pt)
        var bgSnap = wait_for_widget(app, add_item, 6.0f)
        print("bg menu opened -> {bgSnap != null}\n")
        say(app, "show_background_context_menu opens the menu at the cursor; 'Node' creates one here.", add_item)
        click(app, add_item)
        var nSnap = wait_for_widget(app, new_node, 5.0f)
        print("node spawned via bg menu -> {nSnap != null}\n")
        if (nSnap != null) {
            say(app, "A new node, created at the click point.", new_node)
        } else {
            say(app, "(the menu pick did not land)", "{CANVAS}/node_2")
        }
    }
}
