.. _tutorial_ne_connect_by_drag:

##################
Connecting by drag
##################

The signature node-editor gesture: drag from an output pin to an input pin and
a link is created. The interaction lives in a ``begin_create`` scope —
``query_new_link`` reports the pinned pair while the drag hovers a target, and
``accept_new_item`` commits it on release.

.. code-block:: das

   begin_create(g_ed) {
       var a = 0
       var b = 0
       if (query_new_link(g_ed, a, b)) {       // a pin-drag is over a target pin
           if (a != 0 && b != 0 && a != b && accept_new_item(g_ed)) {
               // released on a compatible pin — commit the link
               g_connected = true
           }
       }
   }

The model here is intentionally trivial — one output pin, one input pin, and a
single ``bool``. A real graph validates pin kinds, dedupes, rejects cycles, and
stores a list of links; this just teaches the gesture and the create scope.

Source: ``examples/tutorial/connect_by_drag.das``.

***********
Walkthrough
***********

.. raw:: html

   <video autoplay loop muted playsinline width="100%">
     <source src="../_static/tutorials/connect_by_drag.mp4" type="video/mp4">
     Your browser doesn't support HTML5 video. <a href="../_static/tutorials/connect_by_drag.mp4">Download the recording</a>.
   </video>

.. literalinclude:: ../../../examples/tutorial/connect_by_drag.das
   :language: das
   :linenos:

The create scope
================

``begin_create(ed) { ... }`` opens the editor's create-interaction scope for
the frame. Inside it:

* ``query_new_link(ed, a, b)`` returns ``true`` while a pin-drag is hovering a
  candidate target pin, writing the two pin ids into ``a`` (the drag source) and
  ``b`` (the hovered target). Pins come in **drag order**, so a real handler
  normalizes them to output/input and validates the pair every frame.
* ``accept_new_item(ed)`` returns ``true`` on the frame the user **releases**
  over a valid target — that is where the link is committed. ``reject_new_item``
  is its counterpart for an invalid pair (it shows the reject cursor).

Driving it from a test
=======================

The recording above is produced by a synthetic mouse drag (see
``tests/integration/record_connect_by_drag.das``); the headless regression
``test_connect_drag.das`` drives the same gesture and asserts the link commits.
Grabbing a small pin needs the press to land exactly on it, so the synthetic
timeline parks the cursor on the source pin through the press, travels the full
distance with the button held, then parks on the target pin through the release.

For programmatic link creation that bypasses the mouse entirely (validity-rule
tests), the harness also exposes ``ne_add_link``, which queues a link the same
create handler validates.
