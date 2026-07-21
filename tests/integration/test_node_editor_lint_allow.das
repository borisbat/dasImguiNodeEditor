options gen2
options _comment_hygiene = true

require imgui_node_editor
require imgui/imgui_node_editor_lint

//! Allow-list smoke — default-on lint AND only allow-listed raw calls (the
//! one-time SetNodePosition seed, geometry/selection reads, canvas transforms,
//! and NavigateToContent). Must compile clean.

[export]
def main() {
    imgui_node_editor::SetNodePosition(1, float2(10.0, 20.0))
    let _p = imgui_node_editor::GetNodePosition(1)
    let _s = imgui_node_editor::GetNodeSize(1)
    let _sel = imgui_node_editor::IsNodeSelected(1)
    let _ss = imgui_node_editor::GetScreenSize()
    let _z = imgui_node_editor::GetCurrentZoom()
    let _c = imgui_node_editor::CanvasToScreen(float2(0.0, 0.0))
    imgui_node_editor::NavigateToContent(0.0)
}
