A canvas theme that matches the daslang look. ``apply_daslang_node_editor_style``
comes in two forms: one takes a mutable ``imgui_node_editor::Style`` reference and
retokens it in place (all 19 ``StyleColor`` slots plus the relevant ``StyleVar``
sizes — node rounding, pin radius, link strength, grid and selection colors); the
other takes an ``EditorContext?`` and applies the theme to that editor's live
style, so an app can call it once at startup.
