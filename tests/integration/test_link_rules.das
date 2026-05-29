options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for real-world link validity: dedupe, single-input replace, self-loop
//! rejection, cycle rejection — all driven through ne_add_link (which queues a link the app's
//! create handler validates exactly as a mouse drag would).
//!
//! Two fresh Mul nodes are spawned (deterministic ids off a fresh graph: next_id starts at 14):
//!   A = node 14 (inA 15, inB 16, out 17),  B = node 18 (inA 19, inB 20, out 21).
//! After a valid A.out->B.inA link (link_22), three INVALID adds (duplicate, self-loop, cycle)
//! must allocate NOTHING — proven by the next valid add landing at link_23 (not 26). Then a
//! valid link to an OCCUPIED input replaces the existing one (link_22 gone, link_24 created).

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_link_rules(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        t |> success(ne_wait_widget(s, "node_5", 15.0f) != null, "sample graph rendered")

        // Spawn two Mul nodes (deterministic ids 14 + 18 off the fresh sample graph).
        t |> equal(post_command(d, "spawn_node_cmd", JV((kind = "mul", x = 200.0, y = 500.0)))?["id"] ?? -1, 14,
                   "spawned Mul A as node 14")
        t |> equal(post_command(d, "spawn_node_cmd", JV((kind = "mul", x = 600.0, y = 500.0)))?["id"] ?? -1, 18,
                   "spawned Mul B as node 18")

        // Valid: A.out(17) -> B.inA(19) commits as link_22.
        ne_add_link(s, 17, 19)
        var snap22 = ne_wait_widget(s, "link_22", 6.0f)
        t |> success(snap22 != null, "valid A->B link created (link_22)")
        if (snap22 != null) {
            var l22 = find_widget(snap22, "{s.canvas}/link_22")
            t |> equal(l22?["payload"]?["from_pin"] ?? -1, 17, "link_22 from A.out (17)")
            t |> equal(l22?["payload"]?["to_pin"] ?? -1, 19, "link_22 to B.inA (19)")
        }

        // Three INVALID adds — each must be rejected (allocate nothing):
        ne_add_link(s, 17, 19)    // duplicate of link_22
        ne_add_link(s, 17, 16)    // self-loop (A.out -> A.inB)
        ne_add_link(s, 21, 15)    // cycle (B.out -> A.inA, while A -> B exists)

        // The next VALID add lands at link_23 — proving the 3 rejects consumed no id.
        ne_add_link(s, 17, 20)    // A.out -> B.inB
        var snap23 = ne_wait_widget(s, "link_23", 6.0f)
        t |> success(snap23 != null, "next valid add is link_23 — dedupe/self-loop/cycle allocated nothing")
        if (snap23 != null) {
            t |> equal(find_widget(snap23, "{s.canvas}/link_23")?["payload"]?["to_pin"] ?? -1, 20,
                       "link_23 to B.inB (20)")
            t |> success(!widget_exists(snap23, "{s.canvas}/link_25"),
                         "no stray links from the rejected adds")
        }

        // Replace: a valid link to the OCCUPIED input B.inA (19) drops the existing link_22.
        ne_add_link(s, 2, 19)     // tex.out(2) -> B.inA(19), occupied by link_22
        var snapR = ne_wait_widget(s, "link_24", 6.0f)
        t |> success(snapR != null, "replacement link created (link_24)")
        if (snapR != null) {
            t |> success(!widget_exists(snapR, "{s.canvas}/link_22"),
                         "single-input replace: old link_22 removed")
            var l24 = find_widget(snapR, "{s.canvas}/link_24")
            t |> equal(l24?["payload"]?["from_pin"] ?? -1, 2, "link_24 from tex.out (2)")
            t |> equal(l24?["payload"]?["to_pin"] ?? -1, 19, "link_24 to B.inA (19)")
        }
    }
}
