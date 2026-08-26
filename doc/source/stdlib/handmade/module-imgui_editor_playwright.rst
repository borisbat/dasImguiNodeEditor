Node-editor-aware test layer built on dasImgui's ``imgui_playwright``. ``ne_open``
takes a live ``ImguiApp`` (from ``with_node_editor_app``), waits for the editor to
render, resolves the editor handle from the first snapshot, and returns an
``EditorSession`` that carries the app, the canvas path, and that handle.

The ``ne_*`` helpers then read like a node-editor script rather than raw live
commands: actions (``ne_select_node``, ``ne_add_link``, ``ne_delete_node``,
``ne_move_node``, ``ne_new_node_drag``, ``ne_shortcut``) post the matching
``imgui_node_editor_live`` command against the session's handle; queries
(``ne_snapshot``, ``ne_node``, ``ne_node_exists``, ``ne_node_selected``,
``ne_node_count``, ``ne_payload``) pull fields straight out of the editor payload;
and the polling helpers (``ne_wait_widget``, ``ne_wait_payload_str``,
``ne_wait_shortcut``) wrap the timeout / retry loop so tests don't reinvent it.
