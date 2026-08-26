The v2 DSL for `imgui-node-editor <https://github.com/thedmd/imgui-node-editor>`_.
Every entry point is bracketed by an app-owned ``EditorContext?`` (from
``create_node_editor()`` / ``destroy_node_editor(ctx)``) — there is no singleton,
so one app can drive N editors. ``intptr(ctx)`` is the stable handle that crosses
the live / JSON boundary; ``handle_to_editor(handle)`` reinterprets it back.

The four graph entities are ``forward_argument`` ``[widget]`` / ``[container]``
macros keyed by a runtime integer id (not a state struct), so the app models its
graph however it likes — the editor only needs the ids:

.. code-block:: das

    node_editor(ctx, "shader_graph") <| {
        for (n in graph.nodes) {
            node(n.id) <| {
                text(n.title)
                pin(n.in_pin,  PinKind.Input)  <| { text("in") }
                pin(n.out_pin, PinKind.Output) <| { text("out") }
            }
        }
        for (l in graph.links) {
            link(l.id, l.from_pin, l.to_pin)
        }
    }

Entities register lazily under nested telemetry paths
(``MAIN_WIN/<editor>/node_<id>/pin_<id>``, ``link_<id>``) and build their snapshot
payload only when a snapshot is taken — node ``{id, bbox, selected}``, pin
``{id, kind}``, link ``{id, from_pin, to_pin, selected}``. The editor owns
*geometry* (``NodeId`` is its internal handle; bbox comes from the canvas, seeded
once via ``set_node_position``); the app owns *topology* and reads it back through
the create / delete events.

The function groups below cover the imperative surface: editor lifecycle, node
geometry & view ops, selection, the queue-injectable **link-creation** and
**item-deletion** protocols (``begin_create`` / ``begin_delete`` plus the
``enqueue_*`` rails that replay an action through the same handler the mouse
drives, so headless tests and the live UI share one path), context-menu events,
clipboard & shortcut events, per-scope styling, node-background draw-list access,
and one-shot ``flow`` link animation.
