options gen2

require imgui/imgui_harness
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_node_editor_live

// =============================================================================
// TUTORIAL: context_menus — right-click menus on the canvas, a node, or a link.
//
//   with_suspended() {                              -- enter screen space for popups
//       if (show_node_context_menu(ed, nid)) {      -- right-click landed on a node
//           open_popup("...")                        -- (remember nid, open its menu)
//       } elif (show_background_context_menu(ed, p)) -- right-click on empty canvas
//           open_popup("...")                        -- (remember canvas pos p)
//       popup_window(IDENT, (str_id = "...")) { ... menu_label(...) ... }
//   }
//
// The editor draws in canvas space; popups are plain ImGui in SCREEN space, so the
// detection + the popup windows live inside a Suspend/Resume island (with_suspended).
// The background menu creates a node at the click point; the node menu enqueues a
// delete (enqueue_delete_node) that drains through the same begin_delete accept loop
// the delete tutorial uses — there fed by the native Delete key.
// =============================================================================

struct Nd {
    id      : int
    title   : string
    in_pin  : int
    out_pin : int
    pos     : float2
}

struct Lk {
    id       : int
    from_pin : int
    to_pin   : int
}

var g_nodes    : table<int; Nd>
var g_links    : table<int; Lk>
var g_ed       : imgui_node_editor::EditorContext? = null
var g_seeded   : bool = false
var g_next_id  : int = 200            // ids for menu-created nodes (pins follow: id+1, id+2)
var g_ctx_node : int = 0              // node under a right-click (node menu target)
var g_ctx_pos  : float2               // canvas pos of a background right-click (where to spawn)

var NODE_TITLE : table<int; NarrativeState>   // per-id title slot (data-driven node idiom)

def seed() {
    g_nodes[1] = Nd(id = 1, title = "A", in_pin = 0,  out_pin = 11, pos = float2(120.0, 190.0))
    g_nodes[2] = Nd(id = 2, title = "B", in_pin = 21, out_pin = 0,  pos = float2(480.0, 190.0))
    g_links[100] = Lk(id = 100, from_pin = 11, to_pin = 21)
}

def add_menu_node(pos : float2) {
    let nid = g_next_id
    g_next_id += 10
    g_nodes[nid] = Nd(id = nid, title = "New", in_pin = nid + 1, out_pin = nid + 2, pos = pos)
    imgui_node_editor::SetNodePosition(nid, pos)   // inside the editor block → raw SetNodePosition
}

def remove_node(nid : int) {
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
        // The node menu deletes through the same enqueue / begin_delete rail as the
        // delete tutorial; drain it here.
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
        // Detection + popups run in a Suspend/Resume island (screen space).
        with_suspended() {
            var hit_node = 0
            if (show_node_context_menu(g_ed, hit_node)) {
                g_ctx_node = hit_node
                open_popup("ne_node_menu")
            } elif (show_background_context_menu(g_ed, g_ctx_pos)) {
                open_popup("ne_bg_menu")
            }
            popup_window(NODE_MENU, (str_id = "ne_node_menu", flags = ImGuiWindowFlags.None)) {
                if (menu_label(DEL_ITEM, (text = "Delete node"))) {
                    enqueue_delete_node(g_ed, g_ctx_node)
                }
            }
            popup_window(BG_MENU, (str_id = "ne_bg_menu", flags = ImGuiWindowFlags.None)) {
                text("Add a node")
                if (menu_label(ADD_ITEM, (text = "Node"))) {
                    add_menu_node(g_ctx_pos)
                }
            }
        }
    }
}

[export]
def init() {
    harness_init("Context menus", 1000, 600)
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
    window(MAIN_WIN, (text = "Context menus", closable = false, flags = flags)) {
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
