options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

module imgui_node_editor_boost shared

// Legacy v1 boost — thin block-bracket wrappers over the raw imgui-node-editor
// Begin*/End* pairs. Superseded by `imgui_node_editor_boost_v2` (the telemetry-
// aware, app-owned-context, queue-injectable API). Kept for back-compat; new code
// should require `imgui/imgui_node_editor_boost_v2`.

require imgui public
require imgui_node_editor public

def Begin(name : string; sz : float2; blk : block) {
    Begin(name, sz)
    invoke(blk)
    imgui_node_editor::End()
}

def BeginNode(id : int; blk : block) {
    BeginNode(id)
    invoke(blk)
    EndNode()
}

def BeginPin(id : int; kind : PinKind; blk : block) {
    BeginPin(id, kind)
    invoke(blk)
    EndPin()
}

def BeginCreate(color : float4 = float4(1); thickness : float = 1.0f; blk : block) {
    if (BeginCreate(color, thickness)) {
        invoke(blk)
    }
    EndCreate()
}

def BeginDelete(blk : block) {
    if (BeginDelete()) {
        invoke(blk)
    }
    EndDelete()
}
