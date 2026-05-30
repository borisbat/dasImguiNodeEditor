.. _tutorial_ne_first_graph:

###########
First graph
###########

The four constructs of a node-editor canvas: ``node_editor`` (the canvas),
``node`` (a box), ``pin`` (a connection point), and ``link`` (an edge). The
model is **id-only** — nodes, pins, and links are integer ids you choose; the
editor tracks geometry and interaction, you own what the ids mean.

.. code-block:: das

   g_ed = create_node_editor()              // owns pan / zoom / selection
   node_editor("graph", (editor = g_ed)) {
       node(1) {
           text("Input")
           pin(11, PinKind.Output) { text("value ->") }
       }
       node(2) {
           text("Output")
           pin(21, PinKind.Input) { text("-> value") }
       }
       link(100, 11, 21)                     // output pin 11 -> input pin 21
   }

Source: ``examples/tutorial/first_graph.das``.

***********
Walkthrough
***********

.. raw:: html

   <video autoplay loop muted playsinline width="100%">
     <source src="../_static/tutorials/first_graph.mp4" type="video/mp4">
     Your browser doesn't support HTML5 video. <a href="../_static/tutorials/first_graph.mp4">Download the recording</a>.
   </video>

.. literalinclude:: ../../../examples/tutorial/first_graph.das
   :language: das
   :linenos:

EditorContext
=============

``create_node_editor()`` returns an ``EditorContext?`` that holds the canvas
state — pan, zoom, selection, and node positions. Create it once in ``init``
and ``destroy_node_editor`` it at shutdown. Everything drawn inside
``node_editor(...)`` is positioned in canvas space.

Nodes and pins
==============

``node(id) { ... }`` draws a box; its body is plain ImGui (here a single
``text`` label). ``pin(id, PinKind.Output|Input) { ... }`` adds a connection
point, its body being the pin's label. ``SetNodePosition`` seeds a node's
canvas position once; after that the editor — and the user — own it.

Links
=====

``link(id, from_pin, to_pin)`` draws an edge from an output pin to an input
pin. This graph hard-codes the one link; :ref:`tutorial_ne_connect_by_drag`
makes links with the mouse.
