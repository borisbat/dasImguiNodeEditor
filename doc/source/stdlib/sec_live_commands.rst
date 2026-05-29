.. _stdlib_node_editor_live_commands_section:

*************
Live commands
*************

The ``imgui_node_editor_live`` module registers project-agnostic
``[live_command]`` functions. Each takes a JSON object with ``editor`` — the editor handle
(``intptr(ctx)``, surfaced in the ``node_editor`` snapshot payload) — plus the
fields below, and drives the matching :ref:`boost v2
<stdlib_node_editor_boost_v2_section>` entry point. So an external driver
(dastest, the MCP live API, a tool) can manipulate *any* editor with no app-side
plumbing. Commands are auto-discoverable at runtime via the live ``/commands``
endpoint; ``require imgui/imgui_node_editor_live`` to register them. This module
has no daslang-callable API of its own — it is the JSON drive surface for the
boost layer.

.. list-table::
   :header-rows: 1
   :widths: 26 30 44

   * - Command
     - Input fields (besides ``editor``)
     - Effect
   * - ``move_node``
     - ``id``, ``x``, ``y``
     - Set a node's position (editor coords).
   * - ``select_node_cmd``
     - ``id``, ``on``
     - Select / deselect a node.
   * - ``select_link_cmd``
     - ``id``, ``on``
     - Select / deselect a link.
   * - ``clear_selection_cmd``
     - —
     - Clear all selection.
   * - ``add_link_cmd``
     - ``from``, ``to`` (pin ids)
     - Queue a new link for the editor to create next frame.
   * - ``clear_pending_links_cmd``
     - —
     - Drop all queued (not-yet-created) links.
   * - ``new_node_drag_cmd``
     - ``from`` (pin id), ``x``, ``y``
     - Inject a "new node by drag" release; fires the app's create-node flow.
   * - ``delete_node_cmd``
     - ``id``
     - Queue a node deletion (cascades pins / touching links via the app).
   * - ``delete_link_cmd``
     - ``id``
     - Queue a link deletion.
   * - ``clear_pending_deletes_cmd``
     - —
     - Drop all queued deletions.
   * - ``flow_cmd``
     - ``id``, ``backward`` (optional)
     - One-shot data-flow pulse along a link.
   * - ``center_node_cmd``
     - ``id``
     - Center a node in the viewport.
   * - ``navigate_to_selection_cmd``
     - ``zoom_in`` (opt), ``duration`` (opt)
     - Pan / zoom to frame the current selection.
   * - ``restore_node_state_cmd``
     - ``id``
     - Restore a node's saved position / size from editor settings.
   * - ``set_node_z_cmd``
     - ``id``, ``z``
     - Set a node's draw order (higher draws on top).
   * - ``set_group_size_cmd``
     - ``id``, ``w``, ``h``
     - Resize a group node.
   * - ``ordered_node_ids_cmd``
     - —
     - List node ids in draw order; returns ``count`` + ``ids``.
   * - ``shortcut_cmd``
     - ``kind`` (``cut`` / ``copy`` / ``paste`` / ``duplicate`` / ``create_node``)
     - Inject a clipboard / edit shortcut, replayed through the app's accept handler.
   * - ``clear_pending_shortcuts_cmd``
     - —
     - Drop all queued shortcuts.
   * - ``enable_shortcuts_cmd``
     - ``on``
     - Enable / disable clipboard / edit key chords.
