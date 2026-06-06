options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for the shader_graph.das node-editor demo, end-to-end through the
//! project-agnostic live commands (the imgui_editor_playwright `ne_*` helpers).
//!
//! One host spawn, many subtests: `reset(d)` re-simulates the compiled program into a fresh
//! context between subtests (no recompile), so each starts from the freshly-seeded sample
//! graph — including the deterministic id counter (a fresh app leaves next_id == 14), which
//! several subtests below rely on. ~100x cheaper than respawning daslang-live per [test].
//!
//! Each subtest stays lean on command count to stay under the Windows libhv ~16-POST ceiling.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_shader_graph(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        //! Topology-edit loop: render, add_link, delete_link, delete_node (cascades pins).
        t |> run("topology") <| @(t : T?) {
            // Gate 1+2: canvas rendered → sample graph present, handle exposed.
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
            if (s.handle == uint64(0)) return
            var snap0 = ne_snapshot(s)
            t |> success(ne_node_exists(snap0, s, 5), "sample node_5 present")
            t |> success(widget_exists(snap0, "{s.canvas}/link_11"), "sample link_11 present")

            // Gate 3: add_link injects pin2->pin7 (output->input); app commits link_14.
            ne_add_link(s, 2, 7)
            var snap1 = ne_wait_widget(s, "link_14", 5.0f)
            t |> success(snap1 != null, "ne_add_link created link_14")
            if (snap1 != null) {
                var l14 = find_widget(snap1, "{s.canvas}/link_14")
                t |> equal(l14?["payload"]?["from_pin"] ?? -1, 2, "link_14.from_pin == 2")
                t |> equal(l14?["payload"]?["to_pin"] ?? -1, 7, "link_14.to_pin == 7")
            }

            // Gate 4a: delete_link drops link_11.
            ne_delete_link(s, 11)
            var snap2 = wait_until_sec(d, 5.0f) $(var sn) {
                return !widget_exists(sn, "{s.canvas}/link_11")
            }
            t |> success(snap2 != null, "ne_delete_link removed link_11")

            // Gate 4b: delete_node drops node_5 and cascades its pins.
            ne_delete_node(s, 5)
            var snap3 = wait_until_sec(d, 5.0f) $(var sn) {
                return !ne_node_exists(sn, s, 5)
            }
            t |> success(snap3 != null, "ne_delete_node removed node_5")
            if (snap3 != null) {
                t |> success(!widget_exists(snap3, "{s.canvas}/node_5/pin_6"),
                             "node_5's pin_6 cascaded out")
            }
        }
        reset(d)

        //! flow_cmd / flow() wrapper: transient visual pulse, non-destructive, no telemetry.
        t |> run("flow") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
            if (s.handle == uint64(0)) return

            // Flow an existing sample link — wrapper runs, command returns a response.
            let resp = post_command(d, "flow_cmd", JV((editor = s.handle, id = 11)))
            t |> success(resp != null, "flow_cmd returned a response")

            // Flow is non-destructive: link_11 still present, editor still rendering.
            t |> success(ne_wait_widget(s, "link_11", 5.0f) != null,
                         "link_11 intact after flow (no crash, no topology change)")
        }
        reset(d)

        //! Node ops: z-order folds into node payload; ne_node_count enumerates draw order.
        t |> run("node_ops") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor handle present")
            if (s.handle == uint64(0)) return
            var snap0 = ne_wait_widget(s, "node_5", 15.0f)
            t |> success(snap0 != null, "sample node_5 rendered")
            if (snap0 == null) return

            // z defaults to 0 and folds into node_payload.
            t |> equal(ne_node(snap0, s, 5)?["payload"]?["z"] ?? -1.0, 0.0, "node_5 default z == 0")

            // set_node_z_cmd → observable in a later snapshot.
            post_command(d, "set_node_z_cmd", JV((editor = s.handle, id = 5, z = 5.0)))
            var snapZ = wait_until_sec(d, 5.0f) $(var sn) {
                return (ne_node(sn, s, 5)?["payload"]?["z"] ?? 0.0) >= 4.9
            }
            t |> success(snapZ != null, "set_node_z_cmd: node_5 z surfaced in node_payload")

            // Enumerate draw order — the sample graph has 4 nodes.
            t |> equal(ne_node_count(s), 4, "ordered_node_ids: 4 sample nodes")
        }
        reset(d)

        //! Link validity rules: dedupe, single-input replace, self-loop + cycle rejection.
        t |> run("link_rules") <| @(t : T?) {
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
        reset(d)

        //! node_group entity: registers as node_group_{id} with a lazily-built bbox payload.
        t |> run("node_group") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
            if (s.handle == uint64(0)) return
            t |> success(!widget_exists(ne_snapshot(s), "{s.canvas}/node_group_14"),
                         "no group present initially")

            // Fresh app → the sample graph leaves next_id == 14, so the spawned group is 14.
            let resp = post_command(d, "spawn_group_cmd",
                                    JV((title = "Inputs", x = 60.0, y = 60.0, w = 260.0, h = 300.0)))
            t |> equal(resp?["id"] ?? -1, 14, "spawn_group_cmd returned group id 14")

            var snapG = ne_wait_widget(s, "node_group_14", 6.0f)
            t |> success(snapG != null, "group registered as node_group_14 (distinct kind from node)")
            if (snapG != null) {
                var g14 = find_widget(snapG, "{s.canvas}/node_group_14")
                t |> equal(g14?["payload"]?["id"] ?? -1, 14, "group payload id == 14")
                // A group is geometrically a node — its bbox should be non-degenerate.
                let bx = g14?["payload"]?["bbox"]
                let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
                let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
                t |> success(w > 0.0 && h > 0.0, "group bbox is non-degenerate ({w} x {h})")
                // The group title renders as a child text under the group's path.
                t |> success(widget_exists(snapG, "{s.canvas}/node_group_14/GROUP_TITLE[14]"),
                             "group title text nests under the group")
            }
        }
        reset(d)

        //! Non-telemetry render rails: with_style_var/color compose, pin pivot, group_hint.
        t |> run("render_config") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor handle present")
            if (s.handle == uint64(0)) return
            var snap0 = ne_wait_widget(s, "node_9", 15.0f)
            t |> success(snap0 != null, "styled output node (node_9) rendered")
            if (snap0 == null) return

            // with_style_var (NodeRounding) + with_style_color (NodeBorder) compose around the
            // output node: it still registers with a non-degenerate bbox.
            var n9 = ne_node(snap0, s, 9)
            let bx = n9?["payload"]?["bbox"]
            let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
            let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
            t |> success(w > 0.0 && h > 0.0, "styled output node bbox non-degenerate ({w} x {h})")

            // pivot_scale on the Mul node's output pin (pin_8) — the pin still nests + renders.
            t |> success(widget_exists(snap0, "{s.canvas}/node_5/pin_8"),
                         "output pin with pivot_scale renders (node_5/pin_8)")

            // ===== group_hint active path =====
            let resp = post_command(d, "spawn_group_cmd",
                                    JV((title = "Big Group", x = 60.0, y = 60.0, w = 4000.0, h = 3000.0)))
            t |> equal(resp?["id"] ?? -1, 14, "spawn_group_cmd returned group id 14")
            t |> success(ne_wait_widget(s, "node_group_14", 6.0f) != null, "oversized group registered")

            post_command(d, "navigate_to_content", JV((q = 0)))
            // editor_dims.zoom is InvScale; zoomed-out reads >= 1/0.75 (~1.333). Poll until it settles.
            var zoom = 1.0
            for (_attempt in range(10)) {
                zoom = post_command(d, "editor_dims", JV((q = 0)))?["zoom"] ?? 1.0
                break if (zoom >= 1.34)
                wait_until_sec(d, 0.1f) $(var sn) {
                    return false
                }
            }
            t |> success(zoom >= 1.34, "navigate zoomed out to InvScale {zoom} (>= 1.333) → group_hint active")
            t |> success(ne_wait_widget(s, "node_group_14", 3.0f) != null,
                         "group still renders with group_hint live (no crash)")
        }
        reset(d)

        //! Clipboard/edit shortcuts: duplicate + copy/paste via the injection rail.
        t |> run("shortcuts") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor handle present")
            if (s.handle == uint64(0)) return
            t |> success(ne_wait_widget(s, "node_5", 15.0f) != null, "sample graph rendered")
            t |> equal(ne_node_count(s), 4, "4 sample nodes initially")

            // ---- duplicate: select Mul (node_5), inject Ctrl+D → clone added ----
            ne_clear_selection(s)
            ne_select_node(s, 5, true)
            ne_shortcut(s, "duplicate")
            var snapD = ne_wait_shortcut(s, "duplicate")
            t |> success(snapD != null, "duplicate served (telemetry last_shortcut_action == duplicate)")
            t |> success((ne_payload(snapD, s)?["last_shortcut_context_size"] ?? 0) >= 1,
                         "duplicate action context held the selected node")
            t |> equal(ne_node_count(s), 5, "duplicate added one node (4 -> 5)")

            // ---- copy + paste: select Texture (node_1), inject Ctrl+C then Ctrl+V ----
            ne_clear_selection(s)
            ne_select_node(s, 1, true)
            ne_shortcut(s, "copy")
            t |> success(ne_wait_shortcut(s, "copy") != null, "copy served (telemetry == copy)")

            ne_shortcut(s, "paste")
            t |> success(ne_wait_shortcut(s, "paste") != null, "paste served (telemetry == paste)")
            t |> equal(ne_node_count(s), 6, "paste recreated the copied node (5 -> 6)")
        }
        reset(d)

        //! Clipboard fidelity: copy preserves internal links + relative layout.
        t |> run("clipboard") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor handle present")
            if (s.handle == uint64(0)) return
            t |> success(ne_wait_widget(s, "node_5", 15.0f) != null, "sample graph rendered")
            t |> equal(ne_node_count(s), 4, "4 sample nodes initially")

            // Select the Texture + Multiply pair (joined by link_11), then copy.
            ne_clear_selection(s)
            ne_select_node(s, 1, true)
            ne_select_node(s, 5, true)
            ne_shortcut(s, "copy")
            t |> success(ne_wait_shortcut(s, "copy") != null, "copy served")

            // Paste — poll until link_20 is up and the two pasted nodes have committed their
            // relative layout (~300px x / ~50px y apart, not stacked). Positions are seeded in-frame
            // on first render, so they settle a frame or two after the paste shortcut; gating on the
            // final geometry makes snapP != null itself the layout-preserved proof. An uncommitted
            // node reads imgui-node-editor's un-laid-out sentinel (~INT_MIN), which the band rejects,
            // so the poll only passes once BOTH nodes hold real, correctly-separated positions.
            ne_shortcut(s, "paste")
            var snapP = wait_until_sec(d, 8.0f) $(var snap) {
                if (!widget_exists(snap, "{s.canvas}/link_20")) return false
                let other = widget_exists(snap, "{s.canvas}/node_16") ? 16 : 18
                // canvas_bbox carries the editor canvas-space rect (GetNodePosition); payload.bbox
                // is now screen-space, so the canvas-layout spacing check reads canvas_bbox.
                let bA = find_widget(snap, "{s.canvas}/node_14")?["payload"]?["canvas_bbox"]
                let bB = find_widget(snap, "{s.canvas}/node_{other}")?["payload"]?["canvas_bbox"]
                var dx = (bA?["x"] ?? 0.0) - (bB?["x"] ?? 0.0)
                var dy = (bA?["y"] ?? 0.0) - (bB?["y"] ?? 0.0)
                if (dx < 0.0) {
                    dx = -dx
                }
                if (dy < 0.0) {
                    dy = -dy
                }
                return dx > 250.0 && dx < 350.0 && dy > 20.0 && dy < 80.0
            }
            t |> success(snapP != null,
                         "paste preserved layout: pasted nodes ~300px x / ~50px y apart (not stacked), link_20 up")
            t |> equal(ne_node_count(s), 6, "paste added both nodes (4 -> 6)")

            if (snapP != null) {
                // The copied link connects two PASTED pins (fresh ids >= 15, not the originals <= 10).
                var l20 = find_widget(snapP, "{s.canvas}/link_20")
                t |> success((l20?["payload"]?["from_pin"] ?? 0) >= 15 && (l20?["payload"]?["to_pin"] ?? 0) >= 15,
                             "copied link joins the pasted nodes, not the originals")
            }
        }
        reset(d)

        //! Right-click background context menu opens the Create-Node menu (synth right-click).
        t |> run("context_menu") <| @(t : T?) {
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
            wait_for_mouse_idle(d)

            // The right-click popup is re-showable — gate on actual paint, not stale registry
            // existence (ne_wait_widget can pass on a cached menu entry from a prior open).
            var snapMenu = ne_wait_visible(s, "BG_CTX/CREATE_TEX", 6.0f)
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
        reset(d)

        //! Node-creation-by-drag: drag-release opens the filtered create menu; pick spawns + links.
        t |> run("new_node_drag") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/shader_graph")
            t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
            if (s.handle == uint64(0)) return
            // The filtered menu items aren't at their full path until the menu opens.
            t |> success(!widget_exists(ne_snapshot(s), "{s.canvas}/BG_CTX/CREATE_ADD"),
                         "create-node menu closed initially")

            // Inject a drag-release from pin 8 (Multiply's output) dropped at canvas (600,450).
            ne_new_node_drag(s, 8, 600.0, 450.0)

            // The release opens the Create+Connect menu (re-showable popup) → gate on paint.
            var snapMenu = ne_wait_visible(s, "BG_CTX/CREATE_ADD", 6.0f)
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
}
