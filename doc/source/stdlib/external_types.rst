.. _stdlib_node_editor_external_types_section:

**************
External types
**************

Types defined by C++-bound sister modules — the ``imgui_node_editor`` core
binding, dasImgui's ``imgui`` / ``imgui_playwright`` — that dasImguiNodeEditor
references but does not own. This page anchors their labels so the generated
module pages link without dangling references; follow the upstream links for the
authoritative definitions. (Daslang-core types such as ``json::JsonValue`` resolve
against the `daslang documentation <https://daslang.io/doc/>`_ via intersphinx.)

Node / pin / link ids
=====================

``NodeId``, ``PinId``, and ``LinkId`` are ``int`` type aliases (defined on the
:ref:`boost v2 page <stdlib_node_editor_boost_v2_section>`). They are the editor's
opaque integer handles for graph entities — the app assigns them and the editor
keys everything (geometry, selection, telemetry paths) off them.

.. _handle-imgui_node_editor-EditorContext:

``imgui_node_editor::EditorContext``
====================================

Opaque per-editor handle from `imgui-node-editor
<https://github.com/thedmd/imgui-node-editor>`_ (``ax::NodeEditor::EditorContext``).
Created by ``create_node_editor()``, destroyed by ``destroy_node_editor(ctx)``,
and passed into every boost v2 entry point. ``intptr(ctx)`` is the stable handle
that crosses the live / JSON boundary; ``handle_to_editor(handle)`` reinterprets
it back.

.. _enum-imgui_node_editor-PinKind:

``imgui_node_editor::PinKind``
==============================

Pin direction — ``Input`` or ``Output``. Passed as the second argument to the
``pin`` macro; the editor uses it to decide which side of a node the pin sits on
and which direction a link may flow.

.. _enum-imgui_node_editor-FlowDirection:

``imgui_node_editor::FlowDirection``
====================================

Direction of a ``flow`` pulse along a link — ``Forward`` (source → target, the
default) or ``Backward``.

.. _enum-imgui_node_editor-StyleColor:

``imgui_node_editor::StyleColor``
=================================

The canvas color slots (``Bg``, ``Grid``, ``NodeBg``, ``NodeBorder``,
``HovNodeBorder``, ``SelNodeBorder``, ``Flow``, ``GroupBg``, … plus ``Count``) —
19 in total. Indexed by ``with_style_color`` and retokened wholesale by
:ref:`apply_daslang_node_editor_style <stdlib_node_editor_theme_section>`.

.. _enum-imgui_node_editor-StyleVar:

``imgui_node_editor::StyleVar``
===============================

The canvas style scalars / vectors (``NodePadding``, ``NodeRounding``,
``PinRounding``, ``PinRadius``, ``LinkStrength``, ``PivotAlignment``,
``PivotSize``, ``FlowSpeed``, ``GroupRounding``, …). Pushed for a scope by
``with_style_var`` (float / float2 / float4 overloads matching the var's arity).

.. _handle-imgui-ImDrawList:

``imgui::ImDrawList``
=====================

Dear ImGui's per-window draw-command list, exposed by dasImgui's ``imgui`` module.
The ``group_hint`` and ``with_node_background_drawlist`` blocks hand it to the app
for custom canvas painting (a node's background draw channels only exist *after*
its ``node`` block ends — hence ``with_node_background_drawlist`` runs post-block).
See `ImDrawList in imgui.h <https://github.com/ocornut/imgui/blob/master/imgui.h>`_.

.. _struct-imgui_playwright-ImguiApp:

``imgui_playwright::ImguiApp``
==============================

The live-app handle from dasImgui's ``imgui_playwright`` testing harness — the
base URL, feature path, and transport for a running ``daslang-live`` instance.
``with_node_editor_app`` hands one to its block; ``ne_open`` wraps it in an
:ref:`EditorSession <stdlib_node_editor_testing_section>`. See the
`dasImgui documentation <https://github.com/borisbat/dasImgui>`_.
