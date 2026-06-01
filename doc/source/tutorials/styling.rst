.. _tutorial_ne_styling:

#######
Styling
#######

:ref:`first_graph <tutorial_ne_first_graph>` drew bare boxes. The editor's look is
**layered**, and each layer is independent — reach for the smallest one that does the
job: a canvas-wide **theme**, per-node **tints**, scoped **style var / color** brackets
for one-off nodes, pin **pivots** that move the link-attach point onto the node edge, and
a background **draw list** for custom art.

.. code-block:: das

   apply_daslang_node_editor_style(g_ed)          // canvas theme (warm-dark + amber)

   node(1, (color = float4(0.15, 0.35, 0.18, 0.78))) {   // per-node background tint
       text("Source")
       pin(12, (kind = PinKind.Output, pivot_alignment = float2(1.0, 0.5))) { text("out ->") }
   }

   with_style_var(imgui_node_editor::StyleVar.NodeRounding, 10.0) {        // scoped VAR
       with_style_color(imgui_node_editor::StyleColor.NodeBorder, amber) { // scoped COLOR
           node(3, (color = red)) { ... }
       }
   }
   with_node_background_drawlist(3) $(var dl) {                            // custom art
       let p = imgui_node_editor::GetNodePosition(3)
       let s = imgui_node_editor::GetNodeSize(3)
       dl |> add_rect_filled(p, float2(p.x + 5.0, p.y + s.y), rgba(255u, 90u, 90u, 220u))
   }

Source: ``examples/tutorial/styling.das``.

***********
Walkthrough
***********

.. video:: styling.mp4

.. literalinclude:: ../../../examples/tutorial/styling.das
   :language: das
   :linenos:

Canvas theme
============

``apply_daslang_node_editor_style(ed)`` (from ``imgui/imgui_node_editor_theme_daslang``)
sets the canvas background, grid, and link colors to the warm-dark + amber palette that
matches daslang's ImGui theme. It is one call at ``init`` and affects the whole editor —
the broadest styling layer.

Per-node tint
=============

The ``color`` tuple arg on ``node(id, (color = float4(r, g, b, a)))`` fills that one node's
background. Node 1 is green (a source), node 3 red (an output); node 2 passes no ``color``
and keeps the editor default. This is the cheapest per-node knob — no scope, no restore.

Scoped style var + color
========================

For properties that aren't a node arg — corner rounding, border color — wrap the node in a
scoped bracket. ``with_style_var(StyleVar.NodeRounding, 10.0)`` rounds the corners;
``with_style_color(StyleColor.NodeBorder, amber)`` recolors the border. They **compose**
(nest one inside the other), and each restores the previous value when its block ends, so
only the node inside is affected.

Pin pivots
==========

``pivot_alignment`` on a pin moves the point where links attach. ``float2(0.0, 0.5)`` is
the pin's left edge (use it for inputs), ``float2(1.0, 0.5)`` the right edge (outputs).
Without a pivot the link springs from the pin label's center, which looks untidy once a
node has several pins. (``pivot_size`` and ``pivot_scale`` are the other two knobs — see
``shader_graph.das``.)

Background draw list
====================

``with_node_background_drawlist(id) $(var dl) { ... }`` hands you a draw list **behind** the
node for custom art — here a red accent stripe down node 3's left edge. The node's draw
channels only exist once it is fully built, so this runs **after** the ``node`` block,
reading the editor-owned geometry back with ``GetNodePosition`` / ``GetNodeSize``.
