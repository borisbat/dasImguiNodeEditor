.. _tutorial_ne_groups:

######
Groups
######

A **group** (or comment box) is a node with no pins and an explicit content size — the
editor's tool for visually organizing a large graph. Membership is purely **spatial**:
drag a node *inside* the group's bounds and it travels with the group from then on; drag
it back *out* and the group leaves it behind. There is no "add to group" call.

.. code-block:: das

   node_group(GROUP_ID, (size = float2(300.0, 280.0))) {   // pin-less node; body = label
       text(GROUP_TITLE, (text = "Inputs"))
   }
   group_hint(GROUP_ID) $(var fg; var _bg) {               // off-screen label when zoomed out
       let mn = imgui_node_editor::GetGroupMin()
       fg |> add_text(float2(mn.x + 4.0, mn.y - 18.0), rgba(232u, 226u, 210u, 255u), "Inputs")
   }

Source: ``examples/tutorial/groups.das``.

***********
Walkthrough
***********

.. video:: groups.mp4

The recording is voiced and self-verifying: Texture starts inside the group, Tint outside.
It drags Tint *in* (a group move then carries both nodes), then drags Tint back *out* (a
group move then leaves it behind) — asserting at each step that the right nodes moved and,
crucially, that the outside node stayed put (a no-op aborts at teardown).

.. literalinclude:: ../../../examples/tutorial/groups.das
   :language: das
   :linenos:

A group is a node
=================

``node_group(id, (size = float2(w, h))) { ... }`` is ``BeginNode`` + ``Group(size)``: a
pin-less node whose body is its label. It shares the **same id space** as ``node(id)`` —
keep the ids disjoint (the tutorial uses 1 for the group, 10 / 20 for the nodes). Draw
groups **first** so the regular nodes paint on top of them.

Membership is spatial
=====================

The editor decides what a group carries at the **moment you drag it**: it moves every node
whose bounds fall inside the group's content box (``FindNodesInRect`` over ``m_GroupBounds``
in the C++). There is no membership list and no join API — drop a node inside the bounds and
the next group move takes it along; drag it back outside and the next move leaves it.

To move the group itself, grab its **header** — the title strip *above* the content box.
Pressing the content box instead starts a rubber-band selection (it moves nothing), which
is why the recording aims its group-drag at the title.

Editor-owned geometry
=====================

``size`` is the **initial** content box only. Once the group is placed, the editor owns its
bounds — exactly like a node position. ``SetNodePosition`` seeds the group's canvas position
once; to resize it later call ``set_group_size`` (mutating your own struct's ``size`` field
won't move it). Dragging a node onto the group, or dragging the group itself, is all handled
by the editor — your draw code never changes.

The zoomed-out label
====================

When the canvas is zoomed out far enough that the group's own title is too small to read,
``group_hint(id) $(var fg; var bg) { ... }`` draws a floating label instead. It **self-gates**
— a no-op at normal zoom — so the loop over groups is unconditional. ``GetGroupMin`` returns
the group's top-left (screen space inside a hint); ``fg`` is the foreground hint draw list,
``bg`` the background one. The hint lists swap red/blue for asymmetric colors, so a near-grey
label is the safe choice. See :ref:`navigation <tutorial_ne_navigation>` for zooming the view
out far enough to trigger it.
