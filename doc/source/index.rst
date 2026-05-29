.. dasImguiNodeEditor documentation master file.

dasImguiNodeEditor documentation
================================

Part of the daslang ecosystem. See also the `daslang documentation
<https://daslang.io/doc/>`_, `daslang.io <https://daslang.io>`_, and
`dasImgui <https://github.com/borisbat/dasImgui>`_ — this package's dependency.

dasImguiNodeEditor is the daslang binding for
`imgui-node-editor <https://github.com/thedmd/imgui-node-editor>`_, a node / graph
canvas built on `Dear ImGui <https://github.com/ocornut/imgui>`_. It provides a v2
boost DSL (``node_editor`` / ``node`` / ``pin`` / ``link``), live-reload
integration, a daslang canvas theme, and a Playwright-style testing harness
layered on dasImgui's.

**Source code**: https://github.com/borisbat/dasImguiNodeEditor

**Issues**: https://github.com/borisbat/dasImguiNodeEditor/issues

Install
=======

dasImguiNodeEditor depends on dasImgui; daspkg resolves the dependency:

.. code-block:: bash

   daslang utils/daspkg/main.das -- install github.com/borisbat/dasImguiNodeEditor

Or add to your project's ``.das_package``:

.. code-block:: das

   [export]
   def dependencies(version : string) {
       require_package("github.com/borisbat/dasImguiNodeEditor")
   }

Then run ``daspkg install``.

.. toctree::
   :maxdepth: 2
   :caption: Contents

   stdlib/index
