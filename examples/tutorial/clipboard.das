options gen2
options _comment_hygiene = true

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: clipboard — duplicate / copy / paste via the editor's edit shortcuts.
//
//   with_shortcuts(ed) {                       -- INSIDE node_editor, NOT with_suspended
//       if (accept_copy(ed))      { ... }      -- Ctrl+C fired this frame
//       elif (accept_paste(ed))   { ... }      -- Ctrl+V
//       elif (accept_duplicate(ed)){ ... }     -- Ctrl+D
//   }
//
// imgui-node-editor owns NO clipboard content — accept_* only report that the chord
// fired. The APP owns the clipboard: copy serializes the selected cluster (here: each
// node's title + position relative to the cluster top-left), paste recreates it. accept_*
// runs while the editor is current, so it just FLAGS the action; the actual copy/paste
// runs after the node_editor block (handle_action), where the bracketed selection/spawn
// helpers are safe — the same flag-then-act split the other tutorials use.
//
// Shortcuts are Ctrl+C / Ctrl+V / Ctrl+D on every platform (the editor checks io.KeyCtrl
// directly, so they are NOT remapped to Cmd on macOS) and the editor must be focused —
// clicking a node both selects it and focuses the canvas.
//
// STANDALONE: daslang.exe modules/dasImguiNodeEditor/examples/tutorial/clipboard.das
// LIVE:       daslang-live modules/dasImguiNodeEditor/examples/tutorial/clipboard.das
// =============================================================================

struct Nd {
    id      : int
    title   : string
    out_pin : int
    pos     : float2
}

var g_nodes   : table<int; Nd>
var g_ed      : imgui_node_editor::EditorContext? = null
var g_seeded  : bool = false
var g_next_id : int = 200          // ids for clipboard-created nodes (out pin = id+1)
var g_action  : string = ""        // shortcut accepted this frame; handled AFTER the editor block
var g_paste_anchor : float2        // canvas pos captured at accept_paste (where paste lands)

// App-owned clipboard: each copied node's title + position relative to the cluster
// top-left (g_clip_origin). Paste recreates the cluster, preserving relative layout.
struct ClipNode {
    title : string
    rel   : float2
}
var g_clip        : array<ClipNode>
var g_clip_origin : float2

var NODE_TITLE : table<int; NarrativeState>   // per-id title slot (data-driven node idiom)

def seed() {
    g_nodes[1] = Nd(id = 1, title = "A", out_pin = 11, pos = float2(180.0, 170.0))
    g_nodes[2] = Nd(id = 2, title = "B", out_pin = 21, pos = float2(180.0, 360.0))
}

def spawn(title : string; pos : float2) : int {
    let nid = g_next_id
    g_next_id += 10
    g_nodes[nid] = Nd(id = nid, title = title, out_pin = nid + 1, pos = pos)
    set_node_position(g_ed, nid, pos)   // runs post-editor-block -> bracketed wrapper
    return nid
}

// ===== app-owned clipboard =====

def clipboard_copy() {
    var sel <- get_selected_nodes(g_ed)
    g_clip |> clear()
    var origin = float2(1.0e9, 1.0e9)
    var picked : array<int>
    picked |> reserve(length(sel))
    for (nid in sel) {
        continue if (!key_exists(g_nodes, nid))
        let p = get_node_position(g_ed, nid)
        picked |> push(nid)
        if (p.x < origin.x) {
            origin.x = p.x
        }
        if (p.y < origin.y) {
            origin.y = p.y
        }
    }
    g_clip_origin = empty(picked) ? float2(0.0, 0.0) : origin
    g_clip |> reserve(length(picked))
    for (nid in picked) {
        let p = get_node_position(g_ed, nid)
        g_clip |> push(ClipNode(title = g_nodes[nid].title, rel = p - g_clip_origin))
    }
    delete picked
    delete sel
}

def clipboard_paste(anchor : float2) {
    return if (empty(g_clip))
    clear_selection(g_ed)
    for (ce in g_clip) {
        let nid = spawn(ce.title, anchor + ce.rel)
        select_node(g_ed, nid, true)    // pasted nodes come in selected (chains a follow-up paste)
    }
}

def handle_action() {
    if (g_action == "copy") {
        clipboard_copy()
    } elif (g_action == "paste") {
        clipboard_paste(g_paste_anchor)
    } elif (g_action == "duplicate") {
        clipboard_copy()
        clipboard_paste(g_clip_origin + float2(40.0, 40.0))    // near the originals, layout preserved
    }
    g_action = ""
}

def draw_editor() {
    node_editor("graph", (editor = g_ed)) {
        if (!g_seeded) {
            for (n in values(g_nodes)) {
                imgui_node_editor::SetNodePosition(n.id, n.pos)
            }
            g_seeded = true
        }
        for (n in values(g_nodes)) {
            node(n.id) {
                text(NODE_TITLE[n.id], (text = n.title))
                pin(n.out_pin, PinKind.Output) {
                    text("out ->")
                }
            }
        }
        // Ctrl+C / Ctrl+V / Ctrl+D. accept_* only flags the action (editor is current);
        // handle_action runs the copy/paste post-block where the bracketed helpers are safe.
        with_shortcuts(g_ed) {
            if (accept_copy(g_ed)) {
                g_action = "copy"
            } elif (accept_paste(g_ed)) {
                g_action = "paste"
                // Capture the cursor in canvas space now (editor current). A keyboard paste
                // with no on-canvas cursor (and every headless frame) reads -FLT_MAX, so fall
                // back to just past the copied cluster — the offset duplicate uses.
                g_paste_anchor = (is_mouse_pos_valid()
                    ? imgui_node_editor::ScreenToCanvas(GetMousePos())
                    : g_clip_origin + float2(40.0, 40.0))
            } elif (accept_duplicate(g_ed)) {
                g_action = "duplicate"
            }
        }
    }
    handle_action()
}

[export]
def init() {
    harness_init("Clipboard", 1000, 600)
    g_ed = create_node_editor()
    seed()
}

[export]
def update() {
    if (!harness_begin_frame()) return
    harness_new_frame()
    let io & = unsafe(GetIO())
    SetNextWindowPos(float2(0.0, 0.0), ImGuiCond.Always)
    SetNextWindowSize(io.DisplaySize, ImGuiCond.Always)
    let flags = (ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize |
                 ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoScrollbar |
                 ImGuiWindowFlags.NoScrollWithMouse | ImGuiWindowFlags.NoSavedSettings |
                 ImGuiWindowFlags.NoBringToFrontOnFocus)
    window(MAIN_WIN, (text = "Clipboard", closable = false, flags = flags)) {
        draw_editor()
    }
    harness_end_frame()
}

[export]
def shutdown() {
    destroy_node_editor(g_ed)
    harness_shutdown()
}

[export]
def main() {
    init()
    while (!exit_requested()) {
        update()
    }
    shutdown()
}
