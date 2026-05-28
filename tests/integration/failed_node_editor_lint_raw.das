options gen2

require imgui_node_editor
require imgui/imgui_node_editor_lint

//! Negative test — default-on lint + a raw imgui_node_editor::BeginNode must
//! trip NODEEDITOR001 (macro_error code 50503). No opt-in line required.

expect 50503

[export]
def main() {
    imgui_node_editor::BeginNode(1)
}
