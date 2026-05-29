The integration-test entry point. ``with_node_editor_app(feature_path) <| $(app)
{ ... }`` spawns ``daslang-live`` against a node-editor feature with **both** the
dasImgui and dasImguiNodeEditor modules loaded, runs the block against the live
app, then shuts down — panicking on ready-timeout, test-timeout, or non-zero exit
so the surrounding ``[test]`` fails.

It is a thin delegate over dasImgui's ``imgui_playwright::with_imgui_app``: the
only node-editor-specific knowledge is loading the node-editor module alongside
dasImgui (a daspkg dependency, so it loads after it) and resolving
``modules/dasImguiNodeEditor/...`` feature paths under the node-editor module
root. All the spawn / port / headless / worker-index / ready / shutdown machinery
lives once in ``with_imgui_app``.
