.. _tutorial_ne_navigation:

##########
Navigation
##########

The editor separates the **graph** (node positions, in canvas space) from the **view**
(the pan + zoom that maps canvas to screen). These three ops change only the view — no
node moves: fit the whole graph, frame the selection, or center one node.

.. code-block:: das

   if (button(FIT_ALL, (text = "Fit All"))) {
       g_fit = true                                  // serviced inside the editor block
   }
   if (button(FRAME_SEL, (text = "Frame Selection"))) {
       navigate_to_selection(g_ed, false, -1.0)      // bracketed wrapper → safe out here
   }
   if (button(CENTER_FIRST, (text = "Center #1"))) {
       center_node_on_screen(g_ed, 1)
   }

   node_editor("graph", (editor = g_ed)) {
       ...
       if (g_fit) {
           imgui_node_editor::NavigateToContent(0.0)  // must run with the editor current
           g_fit = false
       }
   }

Source: ``examples/tutorial/navigation.das``.

***********
Walkthrough
***********

.. video:: navigation.mp4

.. literalinclude:: ../../../examples/tutorial/navigation.das
   :language: das
   :linenos:

The three view ops
==================

* ``NavigateToContent(duration)`` — fit the whole graph to the viewport. ``0.0`` snaps
  instantly; a positive duration (seconds) animates a fly-to.
* ``navigate_to_selection(ed, zoomIn, duration)`` — frame just the selected nodes.
* ``center_node_on_screen(ed, nodeId)`` — pan one node to the viewport center.

Placement: inside vs outside the block
======================================

``NavigateToContent`` must run with the editor **current** — i.e. *inside* the
``node_editor`` block. So the "Fit All" button raises a flag and the block services it,
the same flag-then-act pattern the :ref:`context menus <tutorial_ne_context_menus>` use for
deferred work. ``navigate_to_selection`` and ``center_node_on_screen`` are bracketed
wrappers that set the editor current themselves, so the toolbar buttons — which run
*outside* the block — call them directly.

Driving it from a test
======================

The view ops carry no observable state of their own, but they move the view, so a node's
**screen-space** bbox shifts even though its canvas position is unchanged. The graph is
seeded wide (node 3 far to the bottom-right); ``test_navigation.das`` records node 3's
screen center, clicks "Fit All", and asserts the center moved — proof the view changed.
``set_user_control(false)`` hands IO to the synthetic timeline so the real OS cursor can't
race the synth and eat the button click.
