options gen2
options indenting = 4

module imgui_editor_playwright public

// Node-editor test helpers, layered on dasImgui's imgui_playwright. Every node-editor
// test threads three things by hand: the ImguiApp, the editor handle (intptr(ctx) from
// the snapshot), and the canvas path. EditorSession bundles them; the ne_* helpers inject
// the handle into the editor-targeted live commands and wrap the common waits/reads, so a
// test reads as intent ("select node 5, duplicate, expect 6 nodes") rather than JSON plumbing.

require imgui/imgui_playwright public
require imgui/imgui_node_editor_live public   // re-export the *_cmd verbs these wrap
require daslib/json public
require daslib/json_boost public

struct EditorSession {
    app    : ImguiApp
    handle : uint64
    canvas : string         //! snapshot path of the node_editor canvas, e.g. "MAIN_WIN/shader_graph"
}

def public ne_open(app : ImguiApp; canvas : string; timeout_sec : float = 15.0f) : EditorSession {
    //! Wait for `canvas` to render, then pull its editor handle from the node_editor payload.
    //! Returns a session bundling {app, handle, canvas}; handle stays 0 if the canvas never
    //! appeared (the caller should assert `s.handle != 0u`).
    var s = EditorSession(app = app, canvas = canvas, handle = uint64(0))
    var snap = wait_for_widget(app, canvas, timeout_sec)
    if (snap != null) {
        s.handle = find_widget(snap, canvas)?["payload"]?["handle"] ?? uint64(0)
    }
    return s
}

// ===== editor-targeted commands (handle auto-injected) =====

def public ne_select_node(s : EditorSession; id : int; on : bool = true) : JsonValue? {
    return post_command(s.app, "select_node_cmd", JV((editor = s.handle, id = id, on = on)))
}

def public ne_select_link(s : EditorSession; id : int; on : bool = true) : JsonValue? {
    return post_command(s.app, "select_link_cmd", JV((editor = s.handle, id = id, on = on)))
}

def public ne_clear_selection(s : EditorSession) : JsonValue? {
    return post_command(s.app, "clear_selection_cmd", JV((editor = s.handle)))
}

def public ne_shortcut(s : EditorSession; kind : string) : JsonValue? {
    return post_command(s.app, "shortcut_cmd", JV((editor = s.handle, kind = kind)))
}

def public ne_add_link(s : EditorSession; from : int; to : int) : JsonValue? {
    return post_command(s.app, "add_link_cmd", JV((editor = s.handle, from = from, to = to)))
}

def public ne_delete_node(s : EditorSession; id : int) : JsonValue? {
    return post_command(s.app, "delete_node_cmd", JV((editor = s.handle, id = id)))
}

def public ne_delete_link(s : EditorSession; id : int) : JsonValue? {
    return post_command(s.app, "delete_link_cmd", JV((editor = s.handle, id = id)))
}

def public ne_flow(s : EditorSession; link_id : int; backward : bool = false) : JsonValue? {
    return post_command(s.app, "flow_cmd", JV((editor = s.handle, id = link_id, backward = backward)))
}

def public ne_move_node(s : EditorSession; id : int; x : float; y : float) : JsonValue? {
    return post_command(s.app, "move_node", JV((editor = s.handle, id = id, x = x, y = y)))
}

def public ne_new_node_drag(s : EditorSession; from : int; x : float; y : float) : JsonValue? {
    return post_command(s.app, "new_node_drag_cmd", JV((editor = s.handle, from = from, x = x, y = y)))
}

// ===== one-shot reads =====

def public ne_snapshot(s : EditorSession) : JsonValue? {
    //! Fetch a fresh widget snapshot (ne_open keeps only the handle, not its snapshot).
    return snapshot(s.app)
}

def public ne_node_count(s : EditorSession) : int {
    //! Node count via ordered_node_ids_cmd (-1 on failure). One command POST — call after a
    //! wait that confirms the effect landed, not in a poll loop.
    return post_command(s.app, "ordered_node_ids_cmd", JV((editor = s.handle)))?["count"] ?? -1
}

def public ne_payload(var snap : JsonValue?; s : EditorSession) : JsonValue? {
    //! The node_editor canvas payload (handle + last_context_* + last_shortcut_* + …).
    return find_widget(snap, s.canvas)?["payload"]
}

def public ne_node(var snap : JsonValue?; s : EditorSession; id : int) : JsonValue? {
    //! The node entity entry, or a null placeholder if absent (use ne_node_exists to check).
    return find_widget(snap, "{s.canvas}/node_{id}")
}

def public ne_node_exists(var snap : JsonValue?; s : EditorSession; id : int) : bool {
    return widget_exists(snap, "{s.canvas}/node_{id}")
}

def public ne_node_selected(var snap : JsonValue?; s : EditorSession; id : int) : bool {
    return find_widget(snap, "{s.canvas}/node_{id}")?["payload"]?["selected"] ?? false
}

// ===== waits (snapshot-polled) =====

def public ne_wait_widget(s : EditorSession; subpath : string; timeout_sec : float = 6.0f) : JsonValue? {
    //! Poll until `{canvas}/{subpath}` is present (e.g. "node_14", "node_5/pin_8").
    return wait_for_widget(s.app, "{s.canvas}/{subpath}", timeout_sec)
}

def public ne_wait_visible(s : EditorSession; subpath : string; timeout_sec : float = 6.0f) : JsonValue? {
    //! Poll until `{canvas}/{subpath}` is present AND painted this frame. Use for re-showable
    //! widgets (context-menu items, popups): existence-only (ne_wait_widget) can stale-pass on a
    //! cached registry entry before the menu actually repaints.
    return wait_for_visible(s.app, "{s.canvas}/{subpath}", timeout_sec)
}

def public ne_wait_selected(s : EditorSession; id : int; timeout_sec : float = 5.0f) : JsonValue? {
    //! Poll until node `id` is selected. Gate a selection-dependent chord (Ctrl+D / Ctrl+C) on
    //! the click's real effect, not a frame/time guess. Returns the snapshot, or null on timeout.
    return wait_until_sec(s.app, timeout_sec) $(var snap) {
        return ne_node_selected(snap, s, id)
    }
}

def public ne_wait_payload_str(s : EditorSession; field : string; expected : string;
                               timeout_sec : float = 5.0f) : JsonValue? {
    //! Poll until the canvas payload's `field` (a string) equals `expected`. Returns the
    //! matching snapshot or null on timeout.
    return wait_until_sec(s.app, timeout_sec) $(var snap) {
        return (find_widget(snap, s.canvas)?["payload"]?[field] ?? "") == expected
    }
}

def public ne_wait_shortcut(s : EditorSession; action : string; timeout_sec : float = 5.0f) : JsonValue? {
    //! Poll until the editor reports `last_shortcut_action == action` (the injected/real chord
    //! was served). Convenience over ne_wait_payload_str.
    return ne_wait_payload_str(s, "last_shortcut_action", action, timeout_sec)
}
