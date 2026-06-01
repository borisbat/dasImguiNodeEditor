.. _tutorial_ne_delete_and_select:

####################
Deleting & selection
####################

Selection is the editor's job — click a node or link and it highlights. Deleting
the selection runs through a ``begin_delete`` scope: the editor offers each item
being removed, ``accept_deleted_link`` / ``accept_deleted_node`` confirm it, and
**deleting a node cascades** to the links touching its pins.

.. code-block:: das

   begin_delete(g_ed) {
       var lid = 0
       while (query_deleted_link(g_ed, lid)) {       // each link the editor is deleting
           if (accept_deleted_link(g_ed)) {
               g_links |> erase(lid)
           }
       }
       var nid = 0
       while (query_deleted_node(g_ed, nid)) {        // each node being deleted
           if (accept_deleted_node(g_ed)) {
               remove_node(nid)                       // app drops the node + its dangling links
           }
       }
   }

The graph is a tiny ``A -> B -> C`` chain (two links). Deleting the middle node ``B``
removes both links, because the editor reports only the node id — the app cascades
to the links on its pins itself (``remove_node`` below).

Source: ``examples/tutorial/delete_and_select.das``.

***********
Walkthrough
***********

.. video:: delete_and_select.mp4

.. literalinclude:: ../../../examples/tutorial/delete_and_select.das
   :language: das
   :linenos:

The delete scope
================

``begin_delete(ed) { ... }`` opens the editor's delete-interaction scope for the
frame. Inside it:

* ``query_deleted_link(ed, lid)`` / ``query_deleted_node(ed, nid)`` loop over every
  item the editor wants to delete this frame, writing each id out.
* ``accept_deleted_link`` / ``accept_deleted_node`` confirm the removal — the app
  then drops the item from its own model. (``reject_deleted_*`` veto it instead.)

The cascade
===========

A link references two pins; a node *owns* its pins. When a node is deleted the
editor reports only the **node** id, so the app must remove the links whose
endpoints belong to that node — otherwise they dangle. ``remove_node`` snapshots
the link keys first (erasing while iterating ``keys()`` would trip the table's
iterator lock), then erases any link touching the node's input or output pin.

Driving the delete
==================

The editor deletes the current selection on the **Delete key**, routing each removed
item into ``begin_delete`` natively — no app wiring beyond the accept loop above. The
recording selects ``B`` with a click, then presses Delete; the editor raises ``B``
(and the links on its pins) through ``begin_delete`` and the app accepts each one.
``set_user_control(false)`` hands IO to the synthetic timeline so the canvas gains
hover and the Delete key's input gate opens.

For programmatic deletes — a toolbar button, a script step — the same path is reachable
through ``enqueue_delete_node`` / ``enqueue_delete_link``, which the editor replays
through ``begin_delete`` next frame; that enqueue rail is how the test layer deletes
deterministically (``ne_delete_node`` / ``ne_delete_link``).
