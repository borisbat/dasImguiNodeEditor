options gen2
options indenting = 4
options strict_smart_pointers = true

module imgui_node_editor_lint shared private

//! dasImguiNodeEditor lint pass — default-on rule that forbids raw
//! ``imgui_node_editor::*`` calls in consumer code, so the boost_v2 wrappers
//! can't be circumvented. The create/delete wrappers carry the live-command
//! queue-injection logic (enqueue_new_link / enqueue_delete_* replayed through
//! the same begin_create / begin_delete the mouse drives); reaching past them
//! into native ``BeginCreate`` / ``BeginDelete`` silently breaks drivability.
//! node/pin/link, the selection helpers, and the editor lifecycle are wrapped
//! for the same reason (registry/finalize, SetCurrentEditor bracketing).
//!
//! Bundled into ``imgui/imgui_node_editor_boost_v2`` (and therefore everything
//! that transitively requires it). Opt out per-file via
//! ``options _allow_node_editor_native = true``.
//!
//! Code (macro_error severity, error code 50503; gated by the single opt-out):
//!   NODEEDITOR001 — raw ``imgui_node_editor::*`` call not on the allow-list
//!
//! The allow-list (``ALLOWED_NE`` below) is the curated set v2 deliberately
//! doesn't wrap: host-agnostic geometry/selection reads, canvas<->screen
//! transforms, the one-time ``SetNodePosition`` seed (call it inside a
//! ``node_editor`` block where the editor is already current — the bracketed
//! ``set_node_position(ctx, …)`` wrapper covers the out-of-block case), and
//! ``NavigateToContent`` (re-centers the view, no invariant).
//!
//! Scoping: walks ``prog.getThisModule`` only, so the lint runs on the consumer
//! file and skips the transitively-required wrapper modules (which legitimately
//! call raw ``imgui_node_editor::*`` — that's the point of being the wrapper).
//! ``imgui_node_editor_boost_v2`` carries ``options _allow_node_editor_native =
//! true`` so it compiles cleanly when targeted directly (MCP compile_check /
//! lint / daspkg install).

require daslib/ast_boost
require strings

let private ALLOWED_NE : table<string> <- {
    // Geometry / topology / selection reads — pure queries, no host needed (the
    // snapshot serializers use these; consumers may too).
    "GetNodePosition", "GetNodeSize", "GetLinkPins",
    "IsNodeSelected", "IsLinkSelected",
    "HasAnyLinks", "PinHadAnyLinks", "GetNodeCount",
    // Per-frame interaction queries — what the user is hovering / clicked. Pure
    // reads; consumers branch on them to drive context menus, tooltips, etc.
    "GetHoveredNode", "GetHoveredPin", "GetHoveredLink",
    "GetDoubleClickedNode", "GetDoubleClickedPin", "GetDoubleClickedLink",
    "IsBackgroundClicked", "IsBackgroundDoubleClicked",
    "GetBackgroundClickButtonIndex", "GetBackgroundDoubleClickButtonIndex",
    // Editor / node state reads.
    "IsActive", "IsSuspended", "HasSelectionChanged",
    "GetNodeZPosition", "GetGroupMin", "GetGroupMax",
    // Canvas <-> screen transforms + view metrics (read-only).
    "GetScreenSize", "GetCurrentZoom", "CanvasToScreen", "ScreenToCanvas",
    // One-time initial node placement. The editor owns geometry after the first
    // frame; this is the documented in-block seed.
    "SetNodePosition",
    // View navigation — re-centers the canvas, breaks no invariant.
    "NavigateToContent"
}

class NodeEditorLintVisitor : AstVisitor {
    @do_not_delete current_function : Function?

    def override preVisitFunction(var fn : FunctionPtr) : void {
        current_function = fn
    }

    def override visitFunction(var fn : FunctionPtr) : FunctionPtr {
        current_function = null
        return <- fn
    }

    def override preVisitExprCall(var expr : ExprCall?) : void {
        // Combined skip: null guards, macro-generated function bodies, AND
        // macro-synthesized call sites (qmacro ExprCalls whose `at` points at the
        // macro template's file, not the user's) — mirrors imgui_lint.
        if (expr.func == null || expr.func._module == null
                || (current_function != null
                    && (current_function.flags.generated
                        || (current_function.at.fileInfo != null
                            && expr.at.fileInfo != current_function.at.fileInfo)))) return
        let mname = string(expr.func._module.name)
        if (mname == "imgui_node_editor") {
            let fname = string(expr.func.name)
            if (!key_exists(ALLOWED_NE, fname)) {
                compiling_program() |> macro_error(expr.at,
                    "NODEEDITOR001: raw imgui_node_editor::{fname} is forbidden — use the wrapper in modules/dasImguiNodeEditor/daslib/imgui_node_editor_boost_v2.das (node/pin/link, begin_create/begin_delete + query/accept/reject, get_selected_*/select_*/clear_selection, create_node_editor/node_editor). Bypassing the create/delete wrappers breaks live-command queue injection. If {fname} is a genuinely host-agnostic read, extend ALLOWED_NE in imgui_node_editor_lint.das. Per-file escape: `options _allow_node_editor_native = true`.")
            }
        }
    }
}

[lint_macro]
class NodeEditorLintMacro : AstPassMacro {
    def override apply(prog : ProgramPtr; mod : Module?) : bool {
        let opted_out = prog._options |> find_arg("_allow_node_editor_native") ?as tBool ?? false
        if (opted_out) return true
        var v = new NodeEditorLintVisitor()
        make_visitor(*v) $(adapter) {
            visit_module(prog, adapter, prog.getThisModule)
        }
        unsafe { delete v; }
        return true
    }
}
