.. _tutorial_ne_clipboard:

#########
Clipboard
#########

Duplicate, copy, cut and paste are the editor's **edit shortcuts** — Ctrl+D / Ctrl+C /
Ctrl+X / Ctrl+V. imgui-node-editor owns no clipboard content: it only reports that a
chord fired, through a ``with_shortcuts`` scope. The **app** owns the clipboard — here
each copied node's title plus its position relative to the cluster top-left — and
recreates it on paste.

.. code-block:: das

   with_shortcuts(g_ed) {                       // INSIDE node_editor, not with_suspended
       if (accept_copy(g_ed)) {
           g_action = "copy"
       } elif (accept_paste(g_ed)) {
           g_action = "paste"
           g_paste_anchor = ...                 // capture the cursor in canvas space now
       } elif (accept_duplicate(g_ed)) {
           g_action = "duplicate"
       }
   }
   // ... after the node_editor block:
   handle_action()                              // run the copy/paste where the helpers are safe

Source: ``examples/tutorial/clipboard.das``.

***********
Walkthrough
***********

.. video:: clipboard.mp4

.. literalinclude:: ../../../examples/tutorial/clipboard.das
   :language: das
   :linenos:

The app owns the clipboard
==========================

``with_shortcuts(ed) { ... }`` brackets the editor's shortcut scope; inside it,
``accept_copy`` / ``accept_cut`` / ``accept_paste`` / ``accept_duplicate`` each return
true the frame their chord fires. The editor stores nothing — ``accept_copy`` is just
"a Copy happened", and the app responds by serializing its selection. This tutorial's
clipboard is deliberately small (node titles + relative positions); ``shader_graph.das``
shows the full version that also captures the links internal to the selection and remaps
them onto the pasted pins.

Flag now, act later
===================

``accept_*`` runs while the editor is current, so it only **flags** the action
(``g_action``). The real work — ``get_selected_nodes``, ``set_node_position``,
``select_node`` — runs in ``handle_action`` *after* the ``node_editor`` block, where those
bracketed helpers are safe to call. This is the same flag-then-act split the other
tutorials use. Paste captures the cursor anchor at ``accept_paste`` (the editor is current,
so ``ScreenToCanvas`` works), falling back to a fixed offset when there is no on-canvas
cursor — which is every headless frame.

Driving it from a test
======================

The shortcuts are **Ctrl** on every platform: imgui-node-editor checks ``io.KeyCtrl``
directly, so they are *not* remapped to Cmd on macOS the way an ImGui text field is. The
gate is that the editor must be **focused** — a click into the canvas focuses it. So the
recording (see ``tests/integration/record_clipboard.das``) clicks a node — which both
selects it and focuses the canvas — then sends a real Ctrl chord:

.. code-block:: das

   post_command(app, "imgui_key_chord", JV((mods = ["Ctrl"], key = "D")))

The recording app holds ``set_user_control(false)`` for the whole run, so the real OS
cursor can't race the synth and steal the canvas focus the chord needs. It also overlays
the ``imgui_key_hud`` keycap strip, so each ``Ctrl`` chord is visible on screen as it
fires. The headless regression (``test_clipboard_tutorial.das``) drives the same real
chords — distinct from ``test_shortcuts`` / ``test_clipboard``, which exercise
``shader_graph`` through the ``ne_shortcut`` injection rail.
