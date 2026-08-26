options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record navigation.apng - two genuine view ops (Frame Selection / Fit All) and
//! one footgun (Center #1), each fired by a real synthetic click on its toolbar button.
//! Voiced and self-verifying: Fit All and Frame Selection MUST move a node's SCREEN bbox
//! while its CANVAS position holds (record_check_changed + record_check_unchanged) - the
//! proof they move the VIEW. Center #1 is the opposite: it MUST move node 1's CANVAS bbox
//! (record_check_changed) - despite the name, center_node_on_screen relocates the node,
//! not the view. Fit All must also REVEAL node 3 (off-view at the start). A no-op aborts at
//! teardown. The headless regression is test_navigation.das.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // Click the title row, not the center - node 1's center sits on its output pin.
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f, (b?["y"] ?? 0.0f) + 10.0f)
}

def field_json(var snap : JsonValue?; ident : string; field : string) : string {
    return write_json(widget_payload_field(snap, ident, field))
}

def click_node(app : ImguiApp; pt : tuple<float; float>) {
    var ev : array<JsonValue?>
    ev |> click_at(0, pt, 250, 0)
    post_command(app, "imgui_mouse_play", JV((events = ev)))
    wait_for_mouse_idle(app)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/navigation.das",
                                   "navigation.apng", 60) $(app) {
        let T_NODE1 = "{CANVAS}/node_1"
        let T_NODE3 = "{CANVAS}/node_3"
        let FRAME = "MAIN_WIN/FRAME_SEL"
        let FIT = "MAIN_WIN/FIT_ALL"
        let CENTER = "MAIN_WIN/CENTER_FIRST"

        var snap = wait_for_widget(app, T_NODE3, 15.0f)
        if (snap == null) {
            panic("{T_NODE3} never rendered - wrong app running?")
        }
        // At the default view: node 1 full-size top-left, node 3 far off the bottom-right.
        // Capture the before-view screen bboxes and the canvas positions that must never move.
        let n1_bbox0 = field_json(snap, T_NODE1, "bbox")
        let n1_canvas0 = field_json(snap, T_NODE1, "canvas_bbox")
        let n3_bbox0 = field_json(snap, T_NODE3, "bbox")
        let n3_canvas0 = field_json(snap, T_NODE3, "canvas_bbox")
        let n1_title = title_point(snap, T_NODE1)

        // ---- Beat 1: graph vs view ----
        move_to(app, (840.0f, 470.0f), 700)
        wait_for_mouse_idle(app)
        say(app, "graph vs view", "",
            [voice = "The editor splits the graph - the node positions in canvas space - from the view, the pan and zoom onto it. The graph is spread wide, so node three sits far off the bottom-right, out of view."])

        // ---- Beat 2: Frame Selection -> select a real node, then frame just it ----
        click_node(app, n1_title)
        record_check_value(app, T_NODE1, "selected", true)
        click(app, FRAME)
        wait_for_mouse_idle(app)
        record_check_changed(app, T_NODE1, "bbox", n1_bbox0)
        record_check_unchanged(app, T_NODE1, "canvas_bbox", n1_canvas0)
        say(app, "Frame Selection: frame the selected", FRAME,
            [voice = "Select a node, then Frame Selection calls navigate_to_selection to frame just that node - it is a bracketed wrapper, safe to call from the toolbar out here. The view zooms onto node one; its canvas position does not move."])

        // ---- Beat 3: Fit All -> NavigateToContent reveals + reframes the whole graph ----
        click(app, FIT)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE3, true)
        record_check_changed(app, T_NODE3, "bbox", n3_bbox0)
        record_check_unchanged(app, T_NODE3, "canvas_bbox", n3_canvas0)
        say(app, "Fit All: fit the whole graph", FIT,
            [voice = "Fit All raises a flag the editor block services with NavigateToContent, because that one must run with the editor current. It zooms out so the whole graph fits and node three swings into view - again only the view moved."])

        // Node 1 is back on screen - capture its fit-view screen bbox for the Center check.
        var snap1 = snapshot(app)
        let n1_bbox1 = field_json(snap1, T_NODE1, "bbox")

        // ---- Beat 4: Center #1 -> the footgun: it MOVES node 1, not the view ----
        click(app, CENTER)
        wait_for_mouse_idle(app)
        record_check_changed(app, T_NODE1, "canvas_bbox", n1_canvas0)
        record_check_changed(app, T_NODE1, "bbox", n1_bbox1)
        say(app, "Center #1: MOVES node 1 (gotcha)", CENTER,
            [voice = "Center number one is the odd one out. Despite the name, center_node_on_screen moves node one to the view center - watch its canvas position change. Fit All and Frame Selection only moved the view; this one moves the node."])

        // ---- Beat 5: the closer - view ops vs the node move ----
        move_to(app, widget_center(snapshot(app), T_NODE3), 600)
        wait_for_mouse_idle(app)
        record_check_unchanged(app, T_NODE3, "canvas_bbox", n3_canvas0)
        say(app, "view ops vs node move", T_NODE3,
            [voice = "So node three never moved - Fit All and Frame Selection only ever touched the view. Node one moved only because center_node_on_screen relocates it. The name fools you: it centers by moving the node, not by panning."])
    }
}
