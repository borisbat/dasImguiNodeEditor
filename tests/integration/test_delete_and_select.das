options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Headless regression for the delete_and_select tutorial. Select the middle node of an
//! A->B->C chain with a real synthetic click, press the real Delete key, and assert the
//! editor raises it through begin_delete — node B and the two links on its pins cascade
//! out. Mirrors record_delete_and_select.das (the recording driver) without the window.
//! Covers the NATIVE Delete-key path (no enqueue rail).

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/delete_and_select.das"

[test]
def test_delete_and_select(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        let canvas = s.canvas
        var snap = ne_wait_widget(s, "node_2", 15.0f)
        t |> success(snap != null, "A->B->C chain rendered (node_2 present)")
        if (snap == null) return
        t |> equal(ne_node_count(s), 3, "three nodes initially")

        // Title-row click selects B (its center hits a pin, which eats the click).
        let b = find_widget(snap, "{canvas}/node_2")?["bbox"]
        let title_x = ((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f
        let title_y = (b?["y"] ?? 0.0f) + 10.0f
        var ev : array<JsonValue?>
        ev |> click_at(0, (title_x, title_y), 200, 0)
        post_command(d, "imgui_mouse_play", JV((events = ev)))
        wait_for_mouse_idle(d)
        let selected = wait_until_sec(d, 6.0f) $(var sn) {
            return find_widget(sn, "{canvas}/node_2")?["payload"]?["selected"] ?? false
        }
        t |> success(selected != null, "node_2 selected via real synthetic click")

        // Real Delete key — the editor raises the selection through begin_delete.
        let del = int(ImGuiKey.Delete)
        post_command(d, "imgui_key_press",   JV((key = del)))
        post_command(d, "imgui_key_release", JV((key = del)))
        wait_for_key_idle(d, 4.0f)
        var gone = wait_until_sec(d, 6.0f) $(var sn) {
            return !widget_exists(sn, "{canvas}/node_2")
        }
        t |> success(gone != null, "node_2 deleted via real Delete key")
        let links_gone = (gone != null &&
            !widget_exists(gone, "{canvas}/link_100") &&
            !widget_exists(gone, "{canvas}/link_101"))
        t |> success(links_gone, "both links on node_2's pins cascaded out")
        t |> equal(ne_node_count(s), 2, "two nodes remain (A and C)")
    }
}
