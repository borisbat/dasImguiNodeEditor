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
