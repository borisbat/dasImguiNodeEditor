options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record groups.apng - group membership is spatial. Texture starts INSIDE the
//! group, Tint OUTSIDE. Drag Tint in and a group move carries it; drag Tint back out and
//! a group move leaves it behind. Voiced and self-verifying: each drag/move MUST move the
//! nodes it should (record_check_changed) and the out-node MUST stay put when the group
//! moves (record_check_unchanged), or the recording aborts at teardown. This tutorial has
//! no links, so there is no flow pulse. The headless regression is test_groups.das.

let CANVAS = "MAIN_WIN/graph"

def bbox(var snap : JsonValue?; ident : string) : float4 {
    let b = find_widget(snap, ident)?["bbox"]
    return float4(b?["x"] ?? 0.0f, b?["y"] ?? 0.0f, b?["z"] ?? 0.0f, b?["w"] ?? 0.0f)
}

def center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = bbox(snap, ident)
    return ((b.x + b.z) * 0.5f, (b.y + b.w) * 0.5f)
}

def title_point(var snap : JsonValue?; ident : string) : tuple<float; float> {
    // A node's title row - grabbing the center would hit the right-aligned pin and start a
    // link drag; the title strip reliably grabs the node body for a move.
    let b = bbox(snap, ident)
    return ((b.x + b.z) * 0.5f, b.y + 10.0f)
}

def cbbox_json(var snap : JsonValue?; ident : string) : string {
    let v = widget_payload_field(snap, ident, "canvas_bbox")
    return v != null ? write_json(v) : ""
}

def do_drag(app : ImguiApp; from, to : tuple<float; float>) {
    // Press on `from`, travel held to `to`, release - the proven committing timeline.
    var events <- [
        JV((t_ms = 0, kind = "move", x = from._0, y = from._1)),
        JV((t_ms = 300, kind = "move", x = from._0, y = from._1)),
        JV((t_ms = 380, kind = "button", button = 0, action = "press")),
        JV((t_ms = 500, kind = "move", x = from._0, y = from._1)),
        JV((t_ms = 1400, kind = "move", x = to._0, y = to._1)),
        JV((t_ms = 1550, kind = "move", x = to._0, y = to._1)),
        JV((t_ms = 1650, kind = "button", button = 0, action = "release")),
        JV((t_ms = 1800, kind = "move", x = to._0, y = to._1))
    ]
    post_command(app, "imgui_mouse_play", JV((events = events)))
    wait_for_mouse_idle(app)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/groups.das",
                                   "groups.apng", 65) $(app) {
        let T_GROUP = "{CANVAS}/node_group_1"
        let T_TITLE = "{CANVAS}/node_group_1/GROUP_TITLE"
        let T_TEX = "{CANVAS}/node_10"
        let T_TINT = "{CANVAS}/node_20"

        var snap = wait_for_widget(app, T_GROUP, 15.0f)
        if (snap == null) {
            panic("{T_GROUP} never rendered - wrong app running?")
        }

        // ---- Beat 1: the setup - one node in, one out ----
        record_check_rendered(app, T_GROUP, true)
        record_check_rendered(app, T_TEX, true)
        record_check_rendered(app, T_TINT, true)
        say(app, "Texture is inside, Tint is outside", T_GROUP,
            [voice = "A group owns the nodes inside its bounds - membership is spatial. Texture sits inside the box; Tint is outside it."])

        // ---- Beat 2: drag Tint INTO the group ----
        snap = snapshot(app)
        let before_tint_in = cbbox_json(snap, T_TINT)
        do_drag(app, title_point(snap, T_TINT), center(snap, T_GROUP))
        record_check_changed(app, T_TINT, "canvas_bbox", before_tint_in)
        say(app, "drag Tint into the group", T_TINT,
            [voice = "Drag Tint into the group's bounds and it becomes a member - no API call, just position."])

        // ---- Beat 3: move the group -> both nodes follow ----
        snap = snapshot(app)
        let before_g1 = cbbox_json(snap, T_GROUP)
        let before_tex1 = cbbox_json(snap, T_TEX)
        let before_tint1 = cbbox_json(snap, T_TINT)
        let grab1 = center(snap, T_TITLE)
        do_drag(app, grab1, (grab1._0 + 170.0f, grab1._1 + 90.0f))
        record_check_changed(app, T_GROUP, "canvas_bbox", before_g1)
        record_check_changed(app, T_TEX, "canvas_bbox", before_tex1)
        record_check_changed(app, T_TINT, "canvas_bbox", before_tint1)
        say(app, "move the group -> both travel with it", T_GROUP,
            [voice = "Move the group now and both nodes travel with it - Texture and the freshly added Tint."])

        // ---- Beat 4: drag Tint back OUT of the group ----
        snap = snapshot(app)
        let before_tint_out = cbbox_json(snap, T_TINT)
        let gb = bbox(snap, T_GROUP)
        do_drag(app, title_point(snap, T_TINT), (gb.z + 150.0f, (gb.y + gb.w) * 0.5f))
        record_check_changed(app, T_TINT, "canvas_bbox", before_tint_out)
        say(app, "drag Tint back out", T_TINT,
            [voice = "Drag Tint back outside the bounds and it leaves the group again."])

        // ---- Beat 5: move the group -> Texture follows, Tint stays ----
        snap = snapshot(app)
        let before_g2 = cbbox_json(snap, T_GROUP)
        let before_tex2 = cbbox_json(snap, T_TEX)
        let before_tint2 = cbbox_json(snap, T_TINT)
        let grab2 = center(snap, T_TITLE)
        do_drag(app, grab2, (grab2._0 - 130.0f, grab2._1 + 70.0f))
        record_check_changed(app, T_GROUP, "canvas_bbox", before_g2)
        record_check_changed(app, T_TEX, "canvas_bbox", before_tex2)
        // Hard self-verify the membership rule: Tint is outside now, so it MUST NOT move.
        record_check_unchanged(app, T_TINT, "canvas_bbox", before_tint2)
        say(app, "move again -> Texture aboard, Tint left behind", T_GROUP,
            [voice = "Move the group one more time - Texture stays aboard, but Tint, now outside, is left behind."])
    }
}
