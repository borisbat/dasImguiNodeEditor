options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record first_graph.apng - a guided, self-verifying tour of the four
//! node-editor constructs (node_editor / node / pin / link), closing with a
//! data-flow pulse along the link. Voiced (terse caption + natural voice); every
//! construct is asserted rendered, so a missing one aborts the recording at teardown.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/first_graph.das",
                                   "first_graph.apng", 55) $(app) {
        let T_NODE1 = "{CANVAS}/node_1"
        let T_PIN11 = "{CANVAS}/node_1/pin_11"
        let T_NODE2 = "{CANVAS}/node_2"
        let T_PIN21 = "{CANVAS}/node_2/pin_21"
        let T_LINK = "{CANVAS}/link_100"

        let s = ne_open(app, CANVAS)
        if (s.handle == uint64(0)) {
            panic("{CANVAS} never rendered / no editor handle - wrong app running?")
        }
        var snap = wait_for_widget(app, T_NODE1, 15.0f)
        if (snap == null) {
            panic("{T_NODE1} never rendered - wrong app running?")
        }

        let c_node1 = widget_center(snap, T_NODE1)
        let c_pin11 = widget_center(snap, T_PIN11)
        let c_pin21 = widget_center(snap, T_PIN21)
        let c_link = widget_center(snap, T_LINK)

        // ---- Beat 1: the canvas ----
        move_to(app, (500.0f, 300.0f), 600)
        wait_for_mouse_idle(app)
        record_check_rendered(app, CANVAS, true)
        say(app, "node_editor: the canvas", "",
            [voice = "The node editor is the canvas. create_node_editor owns pan, zoom and selection, and everything inside is drawn in canvas space."])

        // ---- Beat 2: a node ----
        move_to(app, c_node1, 600)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE1, true)
        say(app, "node(1): a box", T_NODE1,
            [voice = "A node is just a box. Its body is plain ImGui, here a text label. Every node has an integer id you choose."])

        // ---- Beat 3: an output pin ----
        move_to(app, c_pin11, 700)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_PIN11, true)
        say(app, "pin(11): output", T_PIN11,
            [voice = "Node one carries pin eleven, an output connection point."])

        // ---- Beat 4: an input pin ----
        move_to(app, c_pin21, 800)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE2, true)
        record_check_rendered(app, T_PIN21, true)
        say(app, "pin(21): input", T_PIN21,
            [voice = "Node two carries pin twenty-one, the input a link feeds into."])

        // ---- Beat 5: the link ----
        move_to(app, c_link, 800)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_LINK, true)
        say(app, "link(100): 11 -> 21", T_LINK,
            [voice = "A link is one edge joining output pin eleven to input pin twenty-one. The model is id-only: the editor tracks geometry, you own what the ids mean."])

        // ---- Beat 6: pulse the link to show data flow ----
        // A single flow() fades in about a second, so re-pulse across the whole
        // voice dwell to keep the marker train traveling continuously.
        let dwell = say_begin(app, "data flows 11 -> 21", T_LINK,
            [voice = "And we can pulse the link to watch data flow from the output, along the edge, into the input."])
        var pulses = int(dwell) / 500
        if (pulses < 4) { pulses = 4 }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            sleep(interval)
        }
    }
}
