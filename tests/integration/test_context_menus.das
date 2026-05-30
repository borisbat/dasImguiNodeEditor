options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Headless regression for the context_menus tutorial. Right-click a node for its menu
//! and pick "Delete node" with a real synthetic click; right-click empty canvas for the
//! background menu and pick "Node" to spawn one at the click point. Exercises the
//! with_suspended screen-space popup capture — each menu item's bbox must be screen-space
//! correct for the real click to land. Mirrors record_context_menus.das without the
//! window. (Distinct from test_context_menu.das, which drives shader_graph's bg menu but
//! never clicks a menu item.)

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/context_menus.das"

def node_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

def right_click(d : ImguiApp; pt : tuple<float; float>) {
    var ev : array<JsonValue?>
    ev |> click_at(0, pt, 200, 1)   // button 1 = right
    post_command(d, "imgui_mouse_play", JV((events = ev)))
    wait_for_mouse_idle(d)
}

[test]
def test_context_menus(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        let canvas = s.canvas
        var snap = ne_wait_widget(s, "node_1", 15.0f)
        t |> success(snap != null, "seed graph rendered (node_1 present)")
        if (snap == null) return

        let del_item = "{canvas}/NODE_MENU/DEL_ITEM"
        let add_item = "{canvas}/BG_MENU/ADD_ITEM"

        // ---- node menu: right-click node A's body, pick "Delete node" ----
        right_click(d, node_center(snap, "{canvas}/node_1"))
        var menuSnap = ne_wait_widget(s, "NODE_MENU/DEL_ITEM", 6.0f)
        t |> success(menuSnap != null, "right-click on node opened its context menu")
        click(d, del_item)
        var gone = wait_until_sec(d, 6.0f) $(var sn) {
            return !widget_exists(sn, "{canvas}/node_1")
        }
        t |> success(gone != null, "'Delete node' removed node_1 (real click on canvas popup)")

        // ---- background menu: right-click empty canvas, pick "Node" ----
        right_click(d, (720.0, 430.0))
        var bgSnap = ne_wait_widget(s, "BG_MENU/ADD_ITEM", 6.0f)
        t |> success(bgSnap != null, "right-click on empty canvas opened the background menu")
        click(d, add_item)
        var spawned = ne_wait_widget(s, "node_200", 6.0f)
        t |> success(spawned != null, "'Node' created node_200 at the click point (real click)")
    }
}
