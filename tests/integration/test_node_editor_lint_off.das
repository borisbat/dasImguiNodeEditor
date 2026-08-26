options gen2
options _comment_hygiene = true
options _allow_node_editor_native = true

require imgui_node_editor
require imgui/imgui_node_editor_lint

//! Opt-out smoke — imgui_node_editor_lint is loaded and default-on, but
//! _allow_node_editor_native = true disables it. Raw BeginNode compiles cleanly.

[export]
def main() {
    imgui_node_editor::BeginNode(1)
    imgui_node_editor::EndNode()
}
