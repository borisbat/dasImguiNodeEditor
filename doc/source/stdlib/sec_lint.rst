.. _stdlib_node_editor_lint_section:

*************
Consumer lint
*************

dasImguiNodeEditor ships a default-on lint rule that keeps consumer code on the
boost wrappers instead of the raw C++ binding.

**NODEEDITOR001** — *raw* ``imgui_node_editor::*`` *call not on the allow-list*
(``macro_error`` severity, error code ``50503``). The rule is bundled into
``imgui/imgui_node_editor_boost_v2``, so it runs on anything that transitively
requires the boost layer — and it walks the consumer file only, skipping the
wrapper modules (which legitimately call the raw bindings).

The point: the create / delete wrappers carry the live-command queue-injection
logic (``enqueue_new_link`` / ``enqueue_delete_*`` replayed through the same
``begin_create`` / ``begin_delete`` the mouse drives). Reaching past them into
native ``BeginCreate`` / ``BeginDelete`` silently breaks drivability;
``node`` / ``pin`` / ``link``, the selection helpers, and the editor lifecycle are
wrapped for the same registry / ``SetCurrentEditor`` reasons.

**Allow-list.** A curated set the v2 surface deliberately does *not* wrap is
permitted: host-agnostic geometry / topology / selection reads
(``GetNodePosition``, ``GetNodeSize``, ``GetLinkPins``, ``IsNodeSelected``,
``HasAnyLinks``, ``GetNodeCount``, …), per-frame interaction queries
(``GetHoveredNode`` / ``Pin`` / ``Link``, ``GetDoubleClicked*``,
``IsBackgroundClicked``, …), editor / node state reads (``IsActive``,
``IsSuspended``, ``HasSelectionChanged``, ``GetNodeZPosition``, ``GetGroupMin`` /
``Max``), canvas ↔ screen transforms (``CanvasToScreen``, ``ScreenToCanvas``,
``GetScreenSize``, ``GetCurrentZoom``), the one-time ``SetNodePosition`` seed, and
``NavigateToContent``. If a genuinely host-agnostic read is missing, extend
``ALLOWED_NE`` in ``imgui_node_editor_lint.das``.

**Opt out** per file with::

   options _allow_node_editor_native = true
