options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record context_menus.apng - right-click a node for its "Delete node" menu
//! (delete it, the link cascades), then right-click empty canvas for the background
//! "Add a node" menu (create one at the cursor). Voiced and self-verifying: each
//! right-click MUST open the matching menu, the delete MUST remove the node + cascade
//! its link, and the create MUST spawn a node, or the recording aborts at teardown.
//! Pulses the A -> B link first so the cascade reads as cutting a live connection.
//! The headless regression for the same gestures is test_context_menus.das.

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
                                   "context_menus.apng", 60) $(app) {
        let T_A = "{CANVAS}/node_1"
        let T_B = "{CANVAS}/node_2"
        let T_LINK = "{CANVAS}/link_100"
        let DEL_ITEM = "{CANVAS}/NODE_MENU/DEL_ITEM"
        let ADD_ITEM = "{CANVAS}/BG_MENU/ADD_ITEM"
        let NEW_NODE = "{CANVAS}/node_200"

        let s = ne_open(app, CANVAS)
        if (s.handle == uint64(0)) {
            panic("{CANVAS} never rendered / no editor handle - wrong app running?")
        }
        var snap = wait_for_widget(app, T_A, 15.0f)
        if (snap == null) {
            panic("{T_A} never rendered - wrong app running?")
        }
        let cA = center(snap, T_A)
        let bg_pt : tuple<float; float> = (720.0f, 430.0f)   // empty canvas

        // ---- Beat 1: the live link ----
        record_check_rendered(app, T_A, true)
        let dwell = say_begin(app, "A -> B: a live link", T_A,
            [voice = "A and B share a live link - we can pulse it to see data flow before we touch the menus."])
        var pulses = int(dwell) / 500
        if (pulses < 4) { pulses = 4 }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            hold_content(app, interval)
        }

        // ---- Beat 2: right-click A -> node menu ----
        move_to(app, cA, 700)
        wait_for_mouse_idle(app)
        right_click(app, cA)
        // Hard self-verify: the right-click MUST open the node menu.
        record_check_rendered(app, DEL_ITEM, true)
        say(app, "right-click a node -> its menu", DEL_ITEM,
            [voice = "Right-click a node and the editor pops its own context menu - here it offers Delete node."])

        // ---- Beat 3: Delete node -> A + link cascade ----
        click(app, DEL_ITEM)
        // Hard self-verify: A is gone AND its link cascaded out.
        record_check_rendered(app, T_A, false)
        record_check_rendered(app, T_LINK, false)
        say(app, "Delete node -> A + link cascade", T_B,
            [voice = "Delete node enqueues A through begin_delete - the same path the Delete key uses - so A and the link on its pin cascade away."])

        // ---- Beat 4: right-click empty canvas -> background menu ----
        move_to(app, bg_pt, 700)
        wait_for_mouse_idle(app)
        right_click(app, bg_pt)
        // Hard self-verify: the right-click MUST open the background menu.
        record_check_rendered(app, ADD_ITEM, true)
        say(app, "right-click empty -> background menu", ADD_ITEM,
            [voice = "Right-click empty canvas instead and you get the background menu, opened right at the cursor."])

        // ---- Beat 5: Node -> spawned at the click point ----
        click(app, ADD_ITEM)
        // Hard self-verify: the pick MUST spawn the node.
        record_check_rendered(app, NEW_NODE, true)
        say(app, "Node -> created at the click point", NEW_NODE,
            [voice = "Picking Node creates a fresh node exactly where you clicked."])
    }
}
