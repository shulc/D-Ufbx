/// Smoke test — load a small FBX cube from ufbx's own test data,
/// print the scene summary (node count, mesh count), and for the first
/// mesh print the vertex/face counts plus the bounding box of vertex positions.
///
/// Verifies that the static lib (`libufbx.a`) is correctly linked and that
/// the D struct bindings match the live C memory layout.
///
/// Run via:
///   dub run --config=load_fbx          (from the package root)
///
/// Expected output for `blender_272_cube_7400_binary.fbx`:
///   nodes  = 2
///   meshes = 1
///   mesh[0] "Cube": 8 vertices, 6 faces
///   mesh[0] bbox  = [-1.000, 1.000] x [-1.000, 1.000] x [-1.000, 1.000]
///   OK
///
/// Using: extern/ufbx/data/blender_272_cube_7400_binary.fbx
/// (a Blender 2.72 default cube exported to FBX 7400 binary format)
module load_fbx;

import ufbx.c;

import std.stdio  : writefln, writeln, stderr;
import std.string : fromStringz, toStringz;

void main()
{
    // ufbx ships its own test data; pick a tiny well-known file.
    // dub sets the working directory to the package root, so the path is
    // relative to D-Ufbx/.
    immutable fbxPath = "extern/ufbx/data/blender_272_cube_7400_binary.fbx";

    ufbx_error err;  // D zero-initialises value types — no need for memset

    auto scene = ufbx_load_file(fbxPath.toStringz, null, &err);
    if (scene is null) {
        // err.description.data is always valid even on failure
        stderr.writefln("ufbx_load_file failed (%s): %s",
                        err.type,
                        fromStringz(err.description.data));
        // err.info contains extra context (e.g. the missing filename)
        if (err.info_length > 0)
            stderr.writefln("  info: %s", fromStringz(err.info.ptr));
        return;
    }
    scope (exit) ufbx_free_scene(scene);

    writefln("nodes  = %d", scene.nodes.count);
    writefln("meshes = %d", scene.meshes.count);

    if (scene.meshes.count == 0) {
        writeln("(no meshes — nothing to inspect)");
        writeln("OK");
        return;
    }

    // Inspect the first mesh.
    ufbx_mesh* mesh = scene.meshes.data[0];

    // The mesh name lives in the embedded ufbx_element header; in practice
    // you reach it through the owning node.  For convenience, scan nodes to
    // find one that references this mesh and grab its name.
    const(char)* meshName = "(unnamed)";
    for (size_t ni = 0; ni < scene.nodes.count; ni++) {
        ufbx_node* n = scene.nodes.data[ni];
        if (n.mesh is mesh && n.name.data !is null && n.name.length > 0) {
            meshName = n.name.data;
            break;
        }
    }

    writefln("mesh[0] \"%s\": %d vertices, %d faces",
             fromStringz(meshName),
             mesh.num_vertices,
             mesh.num_faces);

    // Bounding box of the logical vertex positions.
    if (mesh.num_vertices > 0) {
        double minX = double.max,  maxX = -double.max;
        double minY = double.max,  maxY = -double.max;
        double minZ = double.max,  maxZ = -double.max;

        for (size_t i = 0; i < mesh.num_vertices; i++) {
            double x = mesh.vertices.data[i].x;
            double y = mesh.vertices.data[i].y;
            double z = mesh.vertices.data[i].z;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (z < minZ) minZ = z;
            if (z > maxZ) maxZ = z;
        }
        writefln("mesh[0] bbox  = [%.3f, %.3f] x [%.3f, %.3f] x [%.3f, %.3f]",
                 minX, maxX, minY, maxY, minZ, maxZ);
    }

    writeln("OK");
}
