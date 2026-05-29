options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public      // ne_* + re-exported imgui_playwright (click)

//! Integration coverage for node-creation-by-drag in shader_graph.das.
//!
//! Pin geometry isn't queryable, so a real pin-drag can't be synth-targeted — ne_new_node_drag
//! injects the drag-release (the drivable twin of dragging from a pin into empty canvas). The
//! rest is driven exactly as a user would: the create-node menu opens (filtered to connectable
//! kinds), and clicking the chosen item BY ITS RENDERED BBOX (`click`) spawns the node and
//! auto-connects it. Asserts the drag telemetry (last_new_node_drag_*), the connectable filter
//! (an output source omits input-less kinds), and the spawned node + auto-link.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_new_node_drag(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
        if (s.handle == uint64(0)) return
        // The filtered menu items aren't at their full path until the menu opens.
        t |> success(!widget_exists(ne_snapshot(s), "{s.canvas}/BG_CTX/CREATE_ADD"),
                     "create-node menu closed initially")

        // Inject a drag-release from pin 8 (Multiply's output) dropped at canvas (600,450).
        ne_new_node_drag(s, 8, 600.0, 450.0)

        // The release opens the Create+Connect menu → its items register at full path.
        var snapMenu = ne_wait_widget(s, "BG_CTX/CREATE_ADD", 6.0f)
        t |> success(snapMenu != null, "drag-release opened the create-node menu")
        if (snapMenu != null) {
            // Telemetry: the editor recorded the drag (source pin + drop point).
            let cp = ne_payload(snapMenu, s)
            t |> equal(cp?["last_new_node_drag_from_pin"] ?? -1, 8, "telemetry: drag source pin == 8")
            t |> equal(cp?["last_new_node_drag_pos"]?["x"] ?? -1.0, 600.0, "telemetry: drop x == 600")
            // Filtered to connectable kinds: source 8 is an output, so input-having kinds show
            // (Color Output) and input-less kinds are omitted (Texture has no input).
            t |> success(widget_exists(snapMenu, "{s.canvas}/BG_CTX/CREATE_OUT"),
                         "menu lists connectable kind (Color Output present)")
            t |> success(!widget_exists(snapMenu, "{s.canvas}/BG_CTX/CREATE_TEX"),
                         "menu omits non-connectable kind (Texture absent — no input)")

            // Pick the kind where it actually rendered (bbox-resolved click).
            click(d, "{s.canvas}/BG_CTX/CREATE_ADD")

            // Spawn: the picked kind creates a new Add node at the drop point.
            var snapNode = ne_wait_widget(s, "node_14", 5.0f)
            t |> success(snapNode != null, "picked kind spawned node_14")
            if (snapNode != null) {
                t |> equal(find_widget(snapNode, "{s.canvas}/node_14/NODE_TITLE[14]")?["payload"]?["value"] ?? "",
                           "Add", "spawned node titled Add")
            }
            // Auto-connect: the link is ENQUEUED on the pick frame and served a frame later —
            // wait for link_18 in its OWN snapshot rather than reusing snapNode.
            var snapLink = ne_wait_widget(s, "link_18", 5.0f)
            t |> success(snapLink != null, "auto-link created")
            if (snapLink != null) {
                var l18 = find_widget(snapLink, "{s.canvas}/link_18")
                t |> equal(l18?["payload"]?["from_pin"] ?? -1, 8, "auto-link from source pin 8")
                t |> equal(l18?["payload"]?["to_pin"] ?? -1, 15, "auto-link to new node's input pin 15")
            }
        }
    }
}
