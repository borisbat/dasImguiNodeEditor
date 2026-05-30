options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record first_graph.apng — a guided tour of the four constructs
//! (node_editor / node / pin / link). Narration only, no interaction. Run with
//! `daslang tests/integration/record_first_graph.das`, then ffmpeg the .apng to .mp4.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/first_graph.das",
                                   "first_graph.apng", 50) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_1", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_1 never rendered — wrong app running?")
        }
        let c_node1 = widget_center(snap, "{CANVAS}/node_1")
        let c_pin11 = widget_center(snap, "{CANVAS}/node_1/pin_11")
        let c_pin21 = widget_center(snap, "{CANVAS}/node_2/pin_21")
        let c_link  = widget_center(snap, "{CANVAS}/link_100")

        move_to(app, c_node1, 600)
        wait_for_mouse_idle(app)
        say(app, "node_editor - the canvas. create_node_editor() owns pan, zoom and selection; everything inside node_editor(...) is drawn in canvas space.", CANVAS)

        move_to(app, c_node1, 700)
        wait_for_mouse_idle(app)
        say(app, "node(1) - a box. Its body is plain ImGui (here just a text label). Nodes are identified by an integer id you choose.", "{CANVAS}/node_1")

        move_to(app, c_pin11, 700)
        wait_for_mouse_idle(app)
        say(app, "pin(11, PinKind.Output) - an output connection point on node 1.", "{CANVAS}/node_1/pin_11")

        move_to(app, c_pin21, 900)
        wait_for_mouse_idle(app)
        say(app, "node(2) carries pin(21, PinKind.Input) - the destination a link feeds into.", "{CANVAS}/node_2/pin_21")

        move_to(app, c_link, 800)
        wait_for_mouse_idle(app)
        say(app, "link(100, 11, 21) - one edge joining output pin 11 to input pin 21. The model is id-only: the editor tracks geometry, you own what the ids mean.", "{CANVAS}/link_100")
    }
}
