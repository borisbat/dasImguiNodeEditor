options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public      // ne_* + re-exported imgui_playwright (click_at)

//! Integration coverage for the right-click context menu in shader_graph.das.
//!
//! Synthesizes a right-click on empty canvas via imgui_mouse_play and asserts the Create-Node
//! menu opens — its items (BG_CTX/CREATE_*) are absent until opened, so their appearance proves
//! the whole chain end-to-end: harness_new_frame's synth tick drains the timeline, the
//! Suspend/Resume + show_background_context_menu wrappers fire, and the popup + menu_labels
//! render. (A regression guard for the synth-IO path — if the right-click never lands the
//! menu never opens.)

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_context_menu(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
        if (s.handle == uint64(0)) return
        // Menu items are absent while the popup is closed.
        t |> success(!widget_exists(ne_snapshot(s), "{s.canvas}/BG_CTX/CREATE_TEX"),
                     "create-node menu closed initially")

        // Synth a right-click (button 1) on empty canvas — click_at moves to the point FIRST,
        // then presses+releases there (one atomic timeline, no drag).
        var ev : array<JsonValue?>
        ev |> click_at(0, (900.0, 450.0), 150, 1)
        post_command(d, "imgui_mouse_play", JV((events = ev)))

        // The right-click opens the popup → its menu_labels register.
        var snapMenu = ne_wait_widget(s, "BG_CTX/CREATE_TEX", 6.0f)
        t |> success(snapMenu != null, "right-click opened the Create-Node menu")
        if (snapMenu != null) {
            t |> success(widget_exists(snapMenu, "{s.canvas}/BG_CTX/CREATE_ADD"),
                         "menu lists every node type (CREATE_ADD present)")
            t |> success(widget_exists(snapMenu, "{s.canvas}/BG_CTX/CREATE_OUT"),
                         "menu lists every node type (CREATE_OUT present)")
            // The editor recorded which context menu fired — observable in the canvas payload,
            // independent of what the app rendered. A background fire clears node/link targets.
            let cp = ne_payload(snapMenu, s)
            t |> equal(cp?["last_context_kind"] ?? "", "background",
                       "editor recorded last_context_kind = background")
            t |> equal(cp?["last_node_context_menu"] ?? -1, 0, "node target cleared on background fire")
            t |> equal(cp?["last_link_context_menu"] ?? -1, 0, "link target cleared on background fire")
        }
    }
}
