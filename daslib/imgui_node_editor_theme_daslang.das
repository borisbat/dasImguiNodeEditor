options gen2
options _comment_hygiene = true
options indenting = 4

options _allow_node_editor_native = true   // this IS the wrapper that owns the ed::Style calls

module imgui_node_editor_theme_daslang shared

require imgui_node_editor public

//! daslang.io palette for the imgui-node-editor canvas — the node-graph peer of
//! :ref:`apply_daslang_theme <function-imgui_theme_daslang_apply_daslang_theme>`.
//! imgui-node-editor keeps its own ``ed::Style`` (separate color slots: canvas
//! ``Bg``/``Grid``, ``NodeBg``/``NodeBorder``, link + selection accents, pins,
//! flow, groups), so the ImGui theme alone leaves the canvas the library's
//! default blue-grey. Call :ref:`apply_daslang_node_editor_style
//! <function-imgui_node_editor_theme_daslang_apply_daslang_node_editor_style>`
//! once after ``create_node_editor`` to paint it warm-dark + amber to match.
//!
//! Only colors + aesthetic rounding/border widths are set — pivots, directions
//! and link-strength stay at editor defaults so per-pin ``pivot_alignment`` and
//! the link routing are untouched.

// ===== Palette (shared with imgui_theme_daslang) =====
let private bg          = float4(0.051f, 0.047f, 0.039f, 1.0f)   // #0d0c0a — canvas
let private nodeBg      = float4(0.110f, 0.098f, 0.075f, 0.94f)  // warm dark, lighter than canvas so nodes pop
let private grid        = float4(0.200f, 0.170f, 0.130f, 0.45f)  // faint warm grid lines
let private border      = float4(0.165f, 0.141f, 0.110f, 1.0f)   // #2a241c
let private amber       = float4(0.910f, 0.631f, 0.227f, 1.0f)   // #e8a13a — accent
let private amberDim    = float4(0.659f, 0.455f, 0.125f, 1.0f)   // #a87420
let private amberSoft   = float4(0.910f, 0.631f, 0.227f, 0.27f)  // selection-rect wash
let private pinHover    = float4(0.227f, 0.180f, 0.122f, 0.60f)  // pin hover highlight
let private groupBg     = float4(0.659f, 0.455f, 0.125f, 0.10f)  // comment-box fill
let private groupBorder = float4(0.659f, 0.455f, 0.125f, 0.55f)

def public apply_daslang_node_editor_style(var style : imgui_node_editor::Style) {
    //! Apply the daslang palette to ``style`` in-place — every ``StyleColor`` slot
    //! plus aesthetic rounding/border widths. Geometry that drives routing
    //! (pivots, directions, link strength) is left at editor defaults.

    // ===== Colors =====
    style.Colors[int(imgui_node_editor::StyleColor.Bg)]                 = bg
    style.Colors[int(imgui_node_editor::StyleColor.Grid)]              = grid
    style.Colors[int(imgui_node_editor::StyleColor.NodeBg)]            = nodeBg
    style.Colors[int(imgui_node_editor::StyleColor.NodeBorder)]        = border
    style.Colors[int(imgui_node_editor::StyleColor.HovNodeBorder)]     = amberDim
    style.Colors[int(imgui_node_editor::StyleColor.SelNodeBorder)]     = amber
    style.Colors[int(imgui_node_editor::StyleColor.NodeSelRect)]       = amberSoft
    style.Colors[int(imgui_node_editor::StyleColor.NodeSelRectBorder)] = amber
    style.Colors[int(imgui_node_editor::StyleColor.HovLinkBorder)]     = amber
    style.Colors[int(imgui_node_editor::StyleColor.SelLinkBorder)]     = amber
    style.Colors[int(imgui_node_editor::StyleColor.HighlightLinkBorder)] = amber
    style.Colors[int(imgui_node_editor::StyleColor.LinkSelRect)]       = amberSoft
    style.Colors[int(imgui_node_editor::StyleColor.LinkSelRectBorder)] = amber
    style.Colors[int(imgui_node_editor::StyleColor.PinRect)]           = pinHover
    style.Colors[int(imgui_node_editor::StyleColor.PinRectBorder)]     = float4(0.0f, 0.0f, 0.0f, 0.0f)
    style.Colors[int(imgui_node_editor::StyleColor.Flow)]              = amber
    style.Colors[int(imgui_node_editor::StyleColor.FlowMarker)]        = amber
    style.Colors[int(imgui_node_editor::StyleColor.GroupBg)]           = groupBg
    style.Colors[int(imgui_node_editor::StyleColor.GroupBorder)]       = groupBorder

    // ===== Shape (tight rounding, matching the daslang ImGui theme) =====
    style.NodeRounding             = 4.0f
    style.NodeBorderWidth          = 1.0f
    style.HoveredNodeBorderWidth   = 2.0f
    style.SelectedNodeBorderWidth  = 2.5f
    style.PinRounding              = 2.0f
    style.GroupRounding            = 2.0f
    style.GroupBorderWidth         = 1.0f
}

def public apply_daslang_node_editor_style(ctx : imgui_node_editor::EditorContext?) : bool {
    //! Convenience overload — brackets ``SetCurrentEditor(ctx)`` and applies the
    //! palette to that editor's ``GetStyle()``. Call once after
    //! ``create_node_editor``. No-op (returns false) for a null ctx.
    return false if (ctx == null)
    imgui_node_editor::SetCurrentEditor(ctx)
    apply_daslang_node_editor_style(imgui_node_editor::GetStyle())
    imgui_node_editor::SetCurrentEditor(null)
    return true
}
