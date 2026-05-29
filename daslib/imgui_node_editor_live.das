options gen2
options indenting = 4

module imgui_node_editor_live shared

// Project-agnostic live commands for the node editor. Each targets an editor by
// its handle (= intptr(ctx), surfaced in the node_editor snapshot payload) and
// an entity id, so they work against ANY graph the app draws — no app state. App-
// specific commands (debug probes, navigation workarounds) stay in the app.

require imgui/imgui_node_editor_boost_v2
require daslib/json
require daslib/json_boost
require live/live_commands

[live_command(description = "Move a node: input editor (handle), id, x, y (editor coords).")]
def move_node(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let x = input?["x"] ?? 0.0
    let y = input?["y"] ?? 0.0
    let ctx = handle_to_editor(handle)
    return JV("moved {id} -> ({x}, {y})") if (set_node_position(ctx, id, float2(x, y)))
    return JV("editor not ready")
}

[live_command(description = "Select/deselect a node: input editor (handle), id, on (bool).")]
def select_node_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let on = input?["on"] ?? true
    select_node(handle_to_editor(handle), id, on)
    return JV("select node {id} = {on}")
}

[live_command(description = "Select/deselect a link: input editor (handle), id, on (bool).")]
def select_link_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let on = input?["on"] ?? true
    select_link(handle_to_editor(handle), id, on)
    return JV("select link {id} = {on}")
}

[live_command(description = "Queue a new link for the editor to create next frame: input editor (handle), from (pin id), to (pin id).")]
def add_link_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let from = input?["from"] ?? 0
    let to = input?["to"] ?? 0
    return JV("queued link {from} -> {to}") if (enqueue_new_link(handle_to_editor(handle), from, to))
    return JV("not queued (null editor or 0 pin)")
}

[live_command(description = "Clear all queued (not-yet-created) links for an editor: input editor (handle).")]
def clear_pending_links_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    clear_pending_links(handle_to_editor(handle))
    return JV("cleared pending links")
}

[live_command(description = "Inject a 'new node by drag' release (drag from a pin into empty canvas): input editor (handle), from (source pin id), x, y (canvas coords). Fires the app's create-node flow next frame.")]
def new_node_drag_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let from = input?["from"] ?? 0
    let x = input?["x"] ?? 0.0
    let y = input?["y"] ?? 0.0
    return JV("queued node-drag from pin {from} @ ({x}, {y})") if (enqueue_new_node_drag(handle_to_editor(handle), from, float2(x, y)))
    return JV("not queued (null editor or 0 pin)")
}

[live_command(description = "Queue a node deletion for the editor to apply next frame: input editor (handle), id (node id).")]
def delete_node_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    return JV("queued delete node {id}") if (enqueue_delete_node(handle_to_editor(handle), id))
    return JV("not queued (null editor or 0 id)")
}

[live_command(description = "Queue a link deletion for the editor to apply next frame: input editor (handle), id (link id).")]
def delete_link_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    return JV("queued delete link {id}") if (enqueue_delete_link(handle_to_editor(handle), id))
    return JV("not queued (null editor or 0 id)")
}

[live_command(description = "Clear all queued (not-yet-applied) deletions for an editor: input editor (handle).")]
def clear_pending_deletes_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    clear_pending_deletes(handle_to_editor(handle))
    return JV("cleared pending deletes")
}

[live_command(description = "Trigger a one-shot data-flow pulse along a link: input editor (handle), id (link id), backward (bool, optional — default forward).")]
def flow_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let backward = input?["backward"] ?? false
    let dir = backward ? imgui_node_editor::FlowDirection.Backward : imgui_node_editor::FlowDirection.Forward
    return JV("flowing link {id}") if (flow(handle_to_editor(handle), id, dir))
    return JV("not flowed (null editor)")
}

[live_command(description = "Center a node in the viewport: input editor (handle), id (node id).")]
def center_node_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    return JV("centered node {id}") if (center_node_on_screen(handle_to_editor(handle), id))
    return JV("not centered (null editor)")
}

[live_command(description = "Pan/zoom the viewport to frame the current selection: input editor (handle), zoom_in (bool, optional), duration (float seconds, optional — negative = editor default).")]
def navigate_to_selection_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let zoom_in = input?["zoom_in"] ?? false
    let duration = input?["duration"] ?? -1.0
    return JV("navigated to selection") if (navigate_to_selection(handle_to_editor(handle), zoom_in, duration))
    return JV("not navigated (null editor)")
}

[live_command(description = "Restore a node's saved position/size from editor settings: input editor (handle), id (node id).")]
def restore_node_state_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    return JV("restored node {id}") if (restore_node_state(handle_to_editor(handle), id))
    return JV("not restored (null editor)")
}

[live_command(description = "Set a node's draw order: input editor (handle), id (node id), z (float — higher draws on top).")]
def set_node_z_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let z = input?["z"] ?? 0.0
    return JV("set node {id} z = {z}") if (set_node_z_position(handle_to_editor(handle), id, z))
    return JV("not set (null editor)")
}

[live_command(description = "Resize a group node: input editor (handle), id (group node id), w, h (size).")]
def set_group_size_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    let id = input?["id"] ?? 0
    let w = input?["w"] ?? 0.0
    let h = input?["h"] ?? 0.0
    return JV("set group {id} size ({w}, {h})") if (set_group_size(handle_to_editor(handle), id, float2(w, h)))
    return JV("not set (null editor)")
}

[live_command(description = "List node ids in editor draw order (back-to-front): input editor (handle). Returns count + ids array.")]
def ordered_node_ids_cmd(input : JsonValue?) : JsonValue? {
    let handle = input?["editor"] ?? uint64(0)
    var ids <- get_ordered_node_ids(handle_to_editor(handle))
    let n = length(ids)
    var arr = JV(ids)    // copies the ids into a fresh JSON array — ids can be freed after
    delete ids
    return JV((count = n, ids = arr))
}
