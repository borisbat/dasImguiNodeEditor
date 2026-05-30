.. _tutorial_ne_context_menus:

#############
Context menus
#############

Right-click the canvas, a node, or a link and the editor tells you what was hit so
you can pop the matching menu. The catch: the editor draws in **canvas space**
(panned and zoomed), but ImGui popups are plain windows in **screen space**. So the
hit-test *and* the popup windows live inside a ``Suspend``/``Resume`` island —
``with_suspended`` — which steps out of the canvas transform for the duration.

.. code-block:: das

   with_suspended() {                                  // step into screen space
       var hit_node = 0
       if (show_node_context_menu(g_ed, hit_node)) {   // right-click landed on a node
           g_ctx_node = hit_node
           open_popup("ne_node_menu")
       } elif (show_background_context_menu(g_ed, g_ctx_pos)) {  // ...on empty canvas
           open_popup("ne_bg_menu")
       }
       popup_window(NODE_MENU, (str_id = "ne_node_menu")) {
           if (menu_label(DEL_ITEM, (text = "Delete node"))) {
               enqueue_delete_node(g_ed, g_ctx_node)   // routes through begin_delete
           }
       }
       popup_window(BG_MENU, (str_id = "ne_bg_menu")) {
           text("Add a node")
           if (menu_label(ADD_ITEM, (text = "Node"))) {
               add_menu_node(g_ctx_pos)                // create at the click point
           }
       }
   }

The background menu creates a node where you clicked; the node menu deletes its node
through the **same** ``enqueue_delete_node`` / ``begin_delete`` rail as the
:ref:`delete tutorial <tutorial_ne_delete_and_select>`.

Source: ``examples/tutorial/context_menus.das``.

***********
Walkthrough
***********

.. raw:: html

   <video autoplay loop muted playsinline width="100%">
     <source src="../_static/tutorials/context_menus.mp4" type="video/mp4">
     Your browser doesn't support HTML5 video. <a href="../_static/tutorials/context_menus.mp4">Download the recording</a>.
   </video>

.. literalinclude:: ../../../examples/tutorial/context_menus.das
   :language: das
   :linenos:

The suspend island
==================

``with_suspended() { ... }`` brackets the body in ``imgui_node_editor::Suspend()`` /
``Resume()`` and, crucially, pushes an **identity item-transform** for the duration so
any widget rendered inside reports its bounding box directly in screen space. Without
that, a popup drawn while the canvas transform is still on the stack would be
double-mapped — its on-screen position and its recorded bbox would disagree, and a
click resolved from the bbox would miss. Everything that is plain ImGui rather than
canvas geometry — the hit-test calls and the popup windows — belongs in here.

Which menu fired
================

* ``show_node_context_menu(ed, nid)`` returns ``true`` on a right-click that landed on
  a node, writing the node id out. ``show_link_context_menu`` is its link counterpart.
* ``show_background_context_menu(ed, pos)`` returns ``true`` for a right-click on empty
  canvas, writing the **canvas-space** position — stash it so the menu's *Node* item can
  create a node exactly where the click happened.

Because the queries clear the other targets when one fires, the editor also exposes
``last_context_kind`` in its telemetry (``background`` / ``node`` / ``link``) — handy
for a headless assertion that the right kind of menu opened.

Driving it from a test
=======================

The recording above is produced by synthetic right-clicks (see
``tests/integration/record_context_menus.das``): right-click the node body for its
menu, right-click empty canvas for the background menu. Because ``with_suspended``
captures each popup item's bbox in screen space, the menu pick is an ordinary
``click`` resolved from that bbox — the same real synthetic click any widget gets —
which lands on *Delete node* / *Node* and fires the delete or create.

The right-click must hit the node **body**; a click on a pin opens the pin menu
instead. ``set_user_control(false)`` hands IO fully to the synthetic timeline so the
real OS cursor can't race the synth and swallow a menu click.
