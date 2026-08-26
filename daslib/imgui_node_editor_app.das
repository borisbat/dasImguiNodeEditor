options gen2
options _comment_hygiene = true
options indenting = 4

module imgui_node_editor_app public

// Node-editor test driver — a thin delegate over dasImgui's generalized
// `imgui_playwright::with_imgui_app`. The only node-editor-specific knowledge
// left here is: load the dasImguiNodeEditor module alongside dasImgui, and
// resolve `modules/dasImguiNodeEditor/...` feature paths under the node-editor
// module root. ALL spawn/port/headless/worker/ready/shutdown machinery lives
// once in with_imgui_app — this used to duplicate it 1:1.

require imgui/imgui_playwright public   // with_imgui_app, ImguiApp, post_command, snapshot, wait_*, find_widget
require daslib/fio                      // dir_name
require daslib/module_path              // get_this_module_dir

def private ne_module_root() : string {
    // get_this_module_dir() = <node-editor-root>/daslib ; one dir up = the root.
    return dir_name(get_this_module_dir())
}

def public with_node_editor_app(feature_path : string;
                                body : block<(app : ImguiApp) : void>) {
    //! Spawn `daslang-live` against a node-editor feature, run `body`, shut down.
    //! The node-editor module goes in as an extra `-load_module` AFTER dasImgui
    //! (always loaded by `with_imgui_app`) — it requires it, so order matters.
    let root = ne_module_root()
    with_imgui_app(feature_path, [root], root, "modules/dasImguiNodeEditor/", body)
}

def public with_node_editor_recording_app(feature_path : string;
                                          output_apng_basename : string;
                                          max_seconds : int;
                                          body : block<(app : ImguiApp) : void>) {
    //! Native-fps recording session; delegates to the fps overload. The pair exists
    //! because gen2's trailing-block sugar can't see through a default parameter
    //! sitting between the last positional and the block.
    with_node_editor_recording_app(feature_path, output_apng_basename, max_seconds, RECORD_FPS, body)
}

def public with_node_editor_recording_app(feature_path : string;
                                          output_apng_basename : string;
                                          max_seconds : int;
                                          fps : int;
                                          body : block<(app : ImguiApp) : void>) {
    //! Record an `.apng` of a node-editor feature — recording counterpart of
    //! `with_node_editor_app`. Same extra `-load_module`; the node-editor root also
    //! roots a relative `feature_path` and the `.apng` asset dir.
    let root = ne_module_root()
    with_recording_app(feature_path, output_apng_basename, max_seconds, fps,
                       [root], root, root, body)
}
