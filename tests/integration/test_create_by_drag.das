options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Headless regression for the create_by_drag tutorial. A REAL synthetic pin-drag from
//! the source output pin into EMPTY canvas fires show_new_node_drag (its live QueryNewNode
//! + AcceptNewItem path), which opens the create-node menu; a real click on a menu item
//! spawns the node at the drop point and enqueue_new_link auto-connects it.
//!
//! Distinct from test_new_node_drag.das, which drives shader_graph through the
//! ne_new_node_drag INJECTION rail (shader_graph's pins have no queryable bbox). The
//! tutorial subject's pins DO render a screen-space bbox, so the drag is a real gesture.

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/create_by_drag.das"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[test]
def test_create_by_drag(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        let canvas = s.canvas

        var snap = ne_wait_widget(s, "node_1/pin_11", 15.0f)
        t |> success(snap != null, "source output pin rendered")
        if (snap == null) return

        let out_c = widget_center(snap, "{canvas}/node_1/pin_11")
        t |> success(out_c._0 > 0.0f, "pin center resolved")
        t |> success(!widget_exists(snap, "{canvas}/node_200"), "no created node before the drag")

        // REAL pin->empty drag: press on the output pin, travel to an empty canvas point,
        // release there. Verbatim timing from test_connect_drag (the proven committing
        // sequence); the only change is the release lands in empty space, not on a pin.
        let dropx = 680.0f
        let dropy = 430.0f
        var events <- [
            JV((t_ms = 0,    kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 350,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 400,  kind = "button", button = 0,   action = "press")),
            JV((t_ms = 500,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 1400, kind = "move",   x = dropx,    y = dropy)),
            JV((t_ms = 1550, kind = "move",   x = dropx,    y = dropy)),
            JV((t_ms = 1650, kind = "button", button = 0,   action = "release")),
            JV((t_ms = 1800, kind = "move",   x = dropx,    y = dropy))
        ]
        post_command(d, "imgui_mouse_play", JV((events = events)))
        wait_for_mouse_idle(d)

        // The release into empty canvas fires show_new_node_drag -> opens the menu.
        var menuSnap = ne_wait_widget(s, "CREATE_MENU/ADD_MUL", 6.0f)
        t |> success(menuSnap != null, "pin->empty drag opened the create-node menu")
        if (menuSnap == null) return

        // Pick "Multiply" by its rendered bbox (a real synthetic click on the popup item).
        click(d, "{canvas}/CREATE_MENU/ADD_MUL")
        var spawned = ne_wait_widget(s, "node_200", 6.0f)
        t |> success(spawned != null, "pick spawned node_200 at the drop point")

        // Auto-link: the source output pin (11) -> the new node's input pin (201).
        var snapLink = ne_wait_widget(s, "link_100", 6.0f)
        t |> success(snapLink != null, "auto-link created (link_100)")
        if (snapLink != null) {
            var l = find_widget(snapLink, "{canvas}/link_100")
            t |> equal(l?["payload"]?["from_pin"] ?? -1, 11, "auto-link from source pin 11")
            t |> equal(l?["payload"]?["to_pin"] ?? -1, 201, "auto-link to new node input pin 201")
        }
    }
}
