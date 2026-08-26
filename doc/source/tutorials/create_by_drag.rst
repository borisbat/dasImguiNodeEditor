.. _tutorial_ne_create_by_drag:

##############
Create by drag
##############

The :ref:`connect by drag <tutorial_ne_connect_by_drag>` tutorial dragged from a pin
onto another pin to make a link. Release that **same** drag in empty canvas instead and
the editor offers to *create* a node there, pre-wired to the pin you started from. The
create scope reports it through ``show_new_node_drag``: it hands back the source pin and
the canvas-space drop point, the app opens its create-node menu, and on a pick it spawns
the node at the drop point and ``enqueue_new_link`` connects the source to it.

.. code-block:: das

   var drag_fired = false
   begin_create(g_ed) {
       var a = 0
       var b = 0
       if (query_new_link(g_ed, a, b)) {                  // pin -> pin: commit a link
           if (a != 0 && b != 0 && a != b && accept_new_item(g_ed)) {
               commit_link(a, b)
           }
       }
       if (show_new_node_drag(g_ed, g_drag_pin, g_drop_pos)) {   // pin -> empty
           drag_fired = true                              // remember source + drop point
       }
   }
   with_suspended() {                                     // the menu is screen-space ImGui
       if (drag_fired) {
           open_popup("ne_create")
       }
       popup_window(CREATE_MENU, (str_id = "ne_create")) {
           if (menu_label(ADD_MUL, (text = "Multiply"))) {
               spawn_and_connect("Multiply")              // spawn + enqueue_new_link
           }
       }
   }

Source: ``examples/tutorial/create_by_drag.das``.

***********
Walkthrough
***********

.. video:: create_by_drag.mp4

The recording is voiced and self-verifying: a real synthetic pin-drag released
in empty canvas must open the create menu, and the menu pick must spawn the node
and commit the auto-link (a no-op aborts at teardown). It closes by pulsing the
freshly enqueued link with ``flow()`` to show the editor-made wire is live.

.. literalinclude:: ../../../examples/tutorial/create_by_drag.das
   :language: das
   :linenos:

The create scope
================

``begin_create(ed) { ... }`` is the same scope that commits a hand-dragged link, and it
serves both gestures of a pin-drag:

* ``query_new_link(ed, a, b)`` reports the pins when the drag is released **on** a pin —
  commit a link, exactly as in connect by drag.
* ``show_new_node_drag(ed, from_pin, drop_pos)`` is true the frame the drag is released
  in **empty** canvas. It hands back the source pin and the canvas-space drop point, and
  is an *event* (one frame), not a scope — open the create-node UI in response.

The popup is plain ImGui, so it lives in a ``with_suspended`` island (screen space) just
like the :ref:`context menus <tutorial_ne_context_menus>`.

The auto-connect
================

A menu pick spawns the node at the drop point and calls
``enqueue_new_link(ed, source_pin, new_input_pin)``. That queued link is **not** added to
the graph directly — it replays through ``begin_create``'s ``query_new_link`` on the next
frame, the same path a mouse-dragged link takes, so ``commit_link`` stores it once. The
app gets one code path for "a link appeared", whether the user dragged it or the editor
created it.

Driving it from a test
======================

The recording is a real synthetic pin-drag (see ``tests/integration/record_create_by_drag.das``):
press on the output pin, travel to an empty point, release. Because the tutorial's pins
render a real screen-space bbox, the drag targets the pin center directly — a genuine
gesture, not an injected one. (``shader_graph``'s pins have no queryable bbox, so its
``test_new_node_drag`` reaches for the ``ne_new_node_drag`` injection rail instead.) The
menu pick is then an ordinary ``click`` resolved from the item's bbox.

``set_user_control(false)`` hands IO to the synthetic timeline so the real OS cursor can't
race the synth and eat the drag or the menu click.
