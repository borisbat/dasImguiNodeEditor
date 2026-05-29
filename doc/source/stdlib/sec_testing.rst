.. _stdlib_node_editor_testing_section:

****************
Testing harness
****************

The node-editor testing toolkit: ``with_node_editor_app`` spawns ``daslang-live``
with both modules loaded for an integration ``[test]``, and the
``imgui_editor_playwright`` layer (``ne_open`` → ``EditorSession`` + ``ne_*``
helpers) drives and inspects the live editor on top of dasImgui's
``imgui_playwright``.

.. toctree::

   generated/imgui_node_editor_app.rst
   generated/imgui_editor_playwright.rst
