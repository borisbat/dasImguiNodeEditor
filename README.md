# dasImguiNodeEditor

[imgui-node-editor](https://github.com/thedmd/imgui-node-editor) bindings for [daslang](https://dascript.org/).

Provides the `imgui_node_editor` module for building node-based editors with daslang.

## Install

```bash
daslang.exe utils/daspkg/main.das -- install github.com/borisbat/dasImguiNodeEditor
```

Or add to your project's `.das_package`:

```das
[export]
def dependencies(version : string) {
    require_package("github.com/borisbat/dasImguiNodeEditor")
}
```

Then run `daspkg install`.

**Note:** This package depends on [dasImgui](https://github.com/borisbat/dasImgui), which will be installed automatically.

## Build

The C++ build step runs automatically during `daspkg install`. To rebuild manually:

```bash
daspkg build dasImguiNodeEditor
```

Or with CMake directly:

```bash
cmake -B modules/dasImguiNodeEditor/_build -S modules/dasImguiNodeEditor -DDASLANG_DIR=<path-to-daslang-root>
cmake --build modules/dasImguiNodeEditor/_build --config Release
```

### Requirements

- daslang SDK (built with dynamic modules support)
- dasImgui package (installed and built)
- CMake 3.16+
- C++17 compiler (MSVC, GCC, Clang)

## Usage

```das
options gen2

require imgui/imgui_node_editor_boost
require imgui/imgui_boost
require imgui_app

[export]
def main() {
    imgui_app("Node Editor") <| $() {
        NewFrame()
        // ... imgui_node_editor API calls ...
        Render()
    }
}
```

Run with `-project_root` pointing to the directory containing `modules/`:

```bash
daslang.exe -project_root . my_app.das
```

## Modules

| Module | Require | Description |
|--------|---------|-------------|
| `imgui_node_editor` | `require imgui/imgui_node_editor_boost` | imgui-node-editor bindings |

## imgui-node-editor version

v0.9.3 (vendored, patched for imgui 1.90.6 compatibility).

## License

MIT
