options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

module imgui_node_editor_app public

// Node-editor test driver — a node-editor-aware mirror of dasImgui's
// `imgui_playwright::with_imgui_app`. The only reason this exists separately is
// that `with_imgui_app` spawns the live subprocess with `-load_module <dasImgui>`
// ONLY and resolves feature paths under the dasImgui root, so it can't drive an
// app whose `require` chain also needs the dasImguiNodeEditor module. This helper
// adds the second `-load_module` and resolves the feature path under the node-
// editor root; everything else (port, headless/worker-index forwarding, ready
// wait, /shutdown, stdout drain, exit-code checks) mirrors with_imgui_app 1:1.
//
// MIGRATION: once the shape settles, fold this into dasImgui by generalizing
// `with_imgui_app` to take extra `-load_module` roots + an app-supplied feature
// root, then drop this module and re-point tests at the generalized helper.

require imgui/imgui_playwright public      // ImguiApp, post_command, snapshot, wait_*, find_widget, wait_until_ready, transport, POST, JV
require daslib/command_line                // get_das_exe / get_das_root / get_user_args
require daslib/fio public                  // popen_argv / fread_to_eof / popen_timed_out / dir_name / path_join / is_absolute
require daslib/clargs                      // find_bool_flag_raw_value / find_flag_raw_value / unwrap_or
require daslib/module_path                 // get_this_module_dir
require strings

let private NE_LIVE_PORT : int = 9090
let private NE_READY_TIMEOUT_SEC : float = 30.0f
let private NE_TEST_TIMEOUT_SEC : float = 120.0f

def private ne_daslang_live_exe() : string {
    let das = get_das_exe()
    if (empty(das)) return ""
    let dir = dir_name(das)
    let bin = get_platform_name() == "windows" ? "daslang-live.exe" : "daslang-live"
    return path_join(dir, bin)
}

def private ne_module_root() : string {
    // get_this_module_dir() = <node-editor-root>/daslib ; one dir up = the root.
    return dir_name(get_this_module_dir())
}

def private dasimgui_root() : string {
    // dasImgui is a sibling of the node-editor package in both layouts:
    // dev D:/DASPKG/{dasImguiNodeEditor,dasImgui}; CI/junction das_root/modules/{...}.
    return path_join(dir_name(ne_module_root()), "dasImgui")
}

def private ne_resolve_feature_path(path : string) : string {
    if (is_absolute(path)) return path
    let prefix = "modules/dasImguiNodeEditor/"
    if (path |> starts_with(prefix)) return path_join(ne_module_root(), slice(path, length(prefix)))
    return path_join(get_das_root(), path)
}

def private ne_wants_headless() : bool {
    let args <- get_user_args()
    let raw = find_bool_flag_raw_value(args, "--headless")
    return (raw |> unwrap_or("false")) == "true"
}

def private ne_worker_index() : int {
    let args <- get_user_args()
    let raw = find_flag_raw_value(args, "--worker-index") |> unwrap_or("0")
    return to_int(raw)
}

def private ne_post_shutdown(app : ImguiApp) {
    POST("{app.base_url}/shutdown", "", {"Content-Type" => "application/json"}) $(resp) {
        // drop the response — the popen exit-code check is the source of truth
    }
}

def public with_node_editor_app(feature_path : string;
                                body : block<(app : ImguiApp) : void>) {
    //! Spawn `daslang-live` against a node-editor feature with BOTH the dasImgui
    //! and dasImguiNodeEditor modules loaded, run `body` while alive, then POST
    //! /shutdown and drain stdout. Panics on ready-timeout, test-timeout, or
    //! non-zero exit so the surrounding [test] fails. Forwards `--headless` and
    //! the dastest `--worker-index N` per-worker port from this process's argv.
    let exe = ne_daslang_live_exe()
    let port = NE_LIVE_PORT + ne_worker_index()
    let app_path = ne_resolve_feature_path(feature_path)
    var argv <- [exe,
        "-load_module", dasimgui_root(),
        "-load_module", ne_module_root(),
        "--live-port={port}",
        app_path]
    if (ne_wants_headless()) {
        argv |> push("--")
        argv |> push("--headless")
        let harness_budget = NE_TEST_TIMEOUT_SEC - 5.0f
        if (harness_budget > 5.0f) {
            argv |> push("--headless-timeout-sec={harness_budget}")
        }
    }
    let base_url = "http://127.0.0.1:{port}"
    var app = ImguiApp(base_url = base_url,
                       feature_path = app_path,
                       transport <- live_api_transport(base_url))
    var captured : string
    var unready = false
    let exit_code = unsafe(popen_argv(argv, NE_TEST_TIMEOUT_SEC, $(f) {
        return if (f == null)
        if (!wait_until_ready(app, NE_READY_TIMEOUT_SEC)) {
            unready = true
            captured = unsafe(fread_to_eof(f))
            return
        }
        invoke(body, app)
        ne_post_shutdown(app)
        captured = unsafe(fread_to_eof(f))
    }))
    if (unready) {
        panic("daslang-live not ready after {NE_READY_TIMEOUT_SEC}s.\nstdout/stderr:\n{captured}")
    }
    if (exit_code == popen_timed_out) {
        panic("daslang-live timed out (>{NE_TEST_TIMEOUT_SEC}s).\nstdout/stderr:\n{captured}")
    }
    if (exit_code != 0) {
        panic("daslang-live exited non-zero ({exit_code}).\nstdout/stderr:\n{captured}")
    }
}
