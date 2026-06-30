# D-Ufbx

D bindings for **[ufbx](https://github.com/ufbx/ufbx)** v0.23.0 — a robust, single-file C99
FBX/OBJ/MTL scene loader (MIT/Unlicense dual).

ufbx is vendored as a git submodule (`extern/ufbx`).  It is compiled into a
static library (`libufbx.a`) via CMake as part of the dub pre-build step, so
no system-level ufbx installation is required.

## Layout

```
extern/ufbx/            — git submodule, pinned to v0.23.0
    ufbx.h / ufbx.c     — the complete ufbx library (single translation unit)
    data/               — sample FBX/OBJ files used by the example
CMakeLists.txt          — builds libufbx.a (no C++ required)
dub.json                — D package: library + load_fbx example configs
source/ufbx/c.d         — D extern(C) bindings (curated load+scene-read subset)
examples/load_fbx.d     — smoke test: load a cube FBX, print summary + bbox
```

## First build

```sh
git submodule update --init --recursive
dub build                          # library config (produces libd-ufbx.a)
dub run --config=load_fbx          # build + run the example
```

The `preBuildCommands-posix` hook in `dub.json` runs CMake to compile
`ufbx.c` into `build/libufbx.a` before the D source is compiled.

## Smoke test

```sh
dub run --config=load_fbx
```

Expected output for `extern/ufbx/data/blender_272_cube_7400_binary.fbx`
(a Blender 2.72 default cube):

```
nodes  = 2
meshes = 1
mesh[0] "Cube": 8 vertices, 6 faces
mesh[0] bbox  = [-1.000, 1.000] x [-1.000, 1.000] x [-1.000, 1.000]
OK
```

## Consuming from another dub project

```json
"dependencies": {
    "d-ufbx": { "path": "../D-Ufbx" }
}
```

Then `import ufbx.c;` and use `ufbx_load_file` / `ufbx_load_memory` /
`ufbx_free_scene`.

## API quick start

```d
import ufbx.c;

// Load from disk (null opts = ufbx defaults)
ufbx_error err;
auto scene = ufbx_load_file("scene.fbx".toStringz, null, &err);
if (!scene) {
    // err.description.data is always valid
    throw new Exception(err.description.data.fromStringz.idup);
}
scope(exit) ufbx_free_scene(scene);

writefln("%d nodes, %d meshes", scene.nodes.count, scene.meshes.count);

// Walk the first mesh
auto mesh = scene.meshes.data[0];
for (size_t i = 0; i < mesh.num_vertices; i++) {
    auto v = mesh.vertices.data[i];
    writefln("  v[%d] = (%.3f, %.3f, %.3f)", i, v.x, v.y, v.z);
}
```

## Binding scope

This is a **curated subset** of the full ufbx API.  Currently bound:

| What | Status |
|---|---|
| `ufbx_load_file` / `ufbx_load_memory` | bound |
| `ufbx_free_scene` / `ufbx_retain_scene` | bound |
| `ufbx_scene` — `nodes`, `meshes`, `root_node` | bound |
| `ufbx_node` — `name`, `parent`, `children`, `mesh` | bound |
| `ufbx_mesh` — `num_vertices`, `num_faces`, `faces`, `vertices` | bound |
| `ufbx_error` — `type`, `description`, `info` | bound |
| Animations, lights, cameras, materials, UVs, deformers | not yet bound |

Extending the bindings is straightforward: copy the relevant `struct` /
`enum` / function declarations from `extern/ufbx/ufbx.h` into
`source/ufbx/c.d`, preserving field order.  Add `static assert` size/offset
checks to guard against future layout changes.

## Static link verification

After building the example, confirm that `libufbx.so` does **not** appear in
`ldd load_fbx` — ufbx is linked statically into the executable.

```sh
ldd load_fbx | grep ufbx   # should print nothing
```

## License

The D bindings (`source/ufbx/c.d`, `CMakeLists.txt`, `dub.json`) are MIT.
ufbx itself (`extern/ufbx`) is MIT / Public Domain (Unlicense) dual — see
`extern/ufbx/LICENSE`.  See `LICENSE` in this repository for the combined notice.
