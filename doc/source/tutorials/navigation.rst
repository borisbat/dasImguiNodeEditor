.. _tutorial_ne_navigation:

##########
Navigation
##########

The editor separates the **graph** (node positions, in canvas space) from the **view**
(the pan + zoom that maps canvas to screen). Two of these ops change only the view — fit
the whole graph, or frame the selection. The third, ``center_node_on_screen``, is a
**footgun**: despite the name it *moves* the node to the view center.

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

Two view ops and one node move
==============================

* ``NavigateToContent(duration)`` — **view**: fit the whole graph to the viewport. ``0.0``
  snaps instantly; a positive duration (seconds) animates a fly-to.
* ``navigate_to_selection(ed, zoomIn, duration)`` — **view**: frame just the selected nodes.
* ``center_node_on_screen(ed, nodeId)`` — **moves the node**, not the view. Despite the
  name, upstream ``CenterNodeOnScreen`` translates the node's bounds to the view center (and
  marks a user position change). Reach for it to recall a stray node, not to navigate.

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

A view op shifts a node's **screen-space** bbox while its **canvas** position holds;
``center_node_on_screen`` is the mirror image — it leaves the view alone and changes the
canvas position. The recording (``record_navigation.das``) and the headless regression
(``test_navigation.das``) exploit both: they assert Fit All and Frame Selection move the
screen bbox but leave the canvas bbox put (``record_check_changed`` + ``record_check_unchanged``),
then assert Center #1 moves the **canvas** bbox — proof it relocates the node, not the view.
The recording app holds ``set_user_control(false)`` so the real OS cursor can't race the
synth and eat a click.
