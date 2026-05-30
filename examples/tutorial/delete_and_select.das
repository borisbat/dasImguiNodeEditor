options gen2

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: delete_and_select — selecting items and the delete cascade.
//
//   begin_delete(ed) {                        -- open the delete-interaction scope
//       while (query_deleted_link(ed, lid)) { -- the editor offers each link being deleted
//           if (accept_deleted_link(ed)) ...  -- confirm: drop it from your model
//       }
//       while (query_deleted_node(ed, nid)) { -- ...then each deleted node
//           if (accept_deleted_node(ed)) ...  -- confirm: drop the node AND its dangling links
//       }
//   }
//
// Selection is the editor's job: click a node (or link) and it highlights. Press
// Delete and the editor raises the selection through begin_delete next frame — we
// accept each item and drop it from our model. Deleting a NODE must cascade to the
// links touching its pins: the editor reports only the node id, so the app drops the
// dangling links itself (remove_node). A->B->C: deleting B takes both links with it.
// =============================================================================

struct Nd {
    id      : int
    title   : string
    in_pin  : int       // 0 when the node has no input pin
    out_pin : int       // 0 when the node has no output pin
    pos     : float2
}

struct Lk {
    id       : int
    from_pin : int
    to_pin   : int
}

var g_nodes  : table<int; Nd>
var g_links  : table<int; Lk>
var g_ed     : imgui_node_editor::EditorContext? = null
var g_seeded : bool = false

// Per-id text slot. A plain text("foo") shares ONE state global per source line, so a
// loop-rendered title collapses every node's snapshot value to the last drawn. Indexed
// text(TABLE[id], (text = …)) gives each id its own slot (the data-driven node idiom).
var NODE_TITLE : table<int; NarrativeState>

def seed() {
    g_nodes[1] = Nd(id = 1, title = "A", in_pin = 0,  out_pin = 11, pos = float2(80.0,  170.0))
    g_nodes[2] = Nd(id = 2, title = "B", in_pin = 21, out_pin = 22, pos = float2(340.0, 170.0))
    g_nodes[3] = Nd(id = 3, title = "C", in_pin = 31, out_pin = 0,  pos = float2(600.0, 170.0))
    g_links[100] = Lk(id = 100, from_pin = 11, to_pin = 21)
    g_links[101] = Lk(id = 101, from_pin = 22, to_pin = 31)
}

def remove_node(nid : int) {
    // The editor reports the deleted node by id only — cascade to the links on its
    // pins ourselves. Snapshot the link keys first: erasing while iterating keys()
    // would trip the table's iterator lock.
    return if (!key_exists(g_nodes, nid))
    let n = g_nodes[nid]
    var dead <- [for (lk in keys(g_links)); lk]
    for (lk in dead) {
        let l = g_links[lk]
        if (l.from_pin == n.in_pin || l.from_pin == n.out_pin ||
            l.to_pin == n.in_pin   || l.to_pin == n.out_pin) {
            g_links |> erase(lk)
        }
    }
    delete dead
    g_nodes |> erase(nid)
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
                if (n.in_pin != 0) {
                    pin(n.in_pin, PinKind.Input) {
                        text("-> in")
                    }
                }
                if (n.out_pin != 0) {
                    pin(n.out_pin, PinKind.Output) {
                        text("out ->")
                    }
                }
            }
        }
        for (l in values(g_links)) {
            link(l.id, l.from_pin, l.to_pin)
        }
        // Processes the deletes the editor raises (e.g. the Delete key on the
        // selection). Links first, then nodes; a deleted node cascades via remove_node.
        begin_delete(g_ed) {
            var lid = 0
            while (query_deleted_link(g_ed, lid)) {
                if (accept_deleted_link(g_ed)) {
                    g_links |> erase(lid)
                }
            }
            var nid = 0
            while (query_deleted_node(g_ed, nid)) {
                if (accept_deleted_node(g_ed)) {
                    remove_node(nid)
                }
            }
        }
    }
}

[export]
def init() {
    harness_init("Delete and select", 1000, 600)
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
    window(MAIN_WIN, (text = "Delete and select", closable = false, flags = flags)) {
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
