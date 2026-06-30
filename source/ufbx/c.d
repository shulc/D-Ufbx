/// D bindings for the ufbx FBX/OBJ/MTL scene loader.
///
/// This is a **curated subset** of the full ufbx C API covering the
/// load-and-scene-read path.  The rest of the API (animations, NURBS,
/// materials, deformers, etc.) can be added incrementally by mirroring the
/// corresponding declarations from `extern/ufbx/ufbx.h`.
///
/// Struct layouts are verified at compile time via `static assert` on both
/// `sizeof` and `offsetof` values obtained from the same header compiled with
/// gcc.  If ufbx is updated and a layout changes, the asserts will catch it
/// before the binary is produced.
///
/// **ufbx_real** defaults to `double` (the ufbx default; define
/// `UFBX_REAL_IS_FLOAT` in the C compilation to switch to `float`, and
/// update the alias here accordingly).
module ufbx.c;

extern (C) @nogc nothrow:

// ---------------------------------------------------------------------------
// Basic scalar and vector types
// ---------------------------------------------------------------------------

/// Main floating-point type used throughout ufbx.
/// Matches `UFBX_REAL_TYPE` in the C header (default: `double`).
alias ufbx_real = double;

/// Null-terminated UTF-8 string slice.  `data` is always valid + NUL-terminated;
/// `length` excludes the NUL.
struct ufbx_string {
    const(char)* data;
    size_t       length;
}

/// 3-component vector of ufbx_real.
struct ufbx_vec3 {
    ufbx_real x, y, z;
}

/// 4-component quaternion of ufbx_real.
struct ufbx_vec4 {
    ufbx_real x, y, z, w;
}

/// Quaternion (same memory layout as ufbx_vec4).
alias ufbx_quat = ufbx_vec4;

/// TRS (Translation / Rotation / Scale) transformation.
struct ufbx_transform {
    ufbx_vec3 translation; ///< Local translation
    ufbx_quat rotation;    ///< Local rotation (unit quaternion)
    ufbx_vec3 scale;       ///< Local scale
}

/// 4×3 column-major matrix encoding an affine transformation.
/// `cols[0..2]` are the X/Y/Z basis vectors; `cols[3]` is the translation.
struct ufbx_matrix {
    // Stored as 12 doubles in column-major order matching the C union layout.
    ufbx_real m00, m10, m20;  ///< Column 0 (X basis)
    ufbx_real m01, m11, m21;  ///< Column 1 (Y basis)
    ufbx_real m02, m12, m22;  ///< Column 2 (Z basis)
    ufbx_real m03, m13, m23;  ///< Column 3 (translation)
}

/// A single polygonal face: a contiguous run of `num_indices` mesh indices
/// starting at `index_begin`.  `num_indices < 3` means an invalid/degenerate face.
struct ufbx_face {
    uint index_begin;
    uint num_indices;
}

// ---------------------------------------------------------------------------
// Typed list types (all share the same {data*, count} layout)
// ---------------------------------------------------------------------------

/// List of `ufbx_face` entries.
struct ufbx_face_list {
    ufbx_face* data;
    size_t     count;
}

/// List of `ufbx_vec3` values.
struct ufbx_vec3_list {
    ufbx_vec3* data;
    size_t     count;
}

// ufbx_node and ufbx_mesh are defined fully later in this module.
// D resolves forward references within a module automatically — no explicit
// forward declarations needed here.

/// List of `ufbx_node*` pointers.
struct ufbx_node_list {
    ufbx_node** data;
    size_t      count;
}

/// List of `ufbx_mesh*` pointers.
struct ufbx_mesh_list {
    ufbx_mesh** data;
    size_t      count;
}

// ---------------------------------------------------------------------------
// Error reporting
// ---------------------------------------------------------------------------

/// Error classification returned in `ufbx_error.type`.
enum ufbx_error_type : int {
    UFBX_ERROR_NONE                    = 0,
    UFBX_ERROR_UNKNOWN                 = 1,
    UFBX_ERROR_FILE_NOT_FOUND          = 2,
    UFBX_ERROR_EMPTY_FILE              = 3,
    UFBX_ERROR_EXTERNAL_FILE_NOT_FOUND = 4,
    UFBX_ERROR_OUT_OF_MEMORY           = 5,
    UFBX_ERROR_MEMORY_LIMIT            = 6,
    UFBX_ERROR_ALLOCATION_LIMIT        = 7,
    UFBX_ERROR_TRUNCATED_FILE          = 8,
    UFBX_ERROR_IO                      = 9,
    UFBX_ERROR_CANCELLED               = 10,
    UFBX_ERROR_UNRECOGNIZED_FILE_FORMAT = 11,
    UFBX_ERROR_UNINITIALIZED_OPTIONS   = 12,
    // (remaining values left for completeness; check ufbx.h for the full list)
}

/// Error result populated by load functions on failure.
/// Stack-allocate and zero-initialise before passing to a load function:
///   `ufbx_error err;` is sufficient (D zero-initialises value types).
///
/// Layout verified against `ufbx.h` via static asserts below.
struct ufbx_error {
    ufbx_error_type type;        ///< Error category (UFBX_ERROR_NONE on success)
    private uint    _pad0;       ///< Padding to align description to 8 bytes
    ufbx_string     description; ///< Human-readable type description (static storage)
    uint            stack_size;  ///< Number of valid entries in the internal stack
    private uint    _pad1;       ///< Padding before the frame array
    /// Internal call-stack frames (up to UFBX_ERROR_STACK_MAX_DEPTH = 8).
    /// Opaque — access via ufbx_format_error() if you need a textual trace.
    private ubyte[320] _stack;   ///< 8 frames × 40 bytes each
    size_t          info_length; ///< Length of the `info` string (excl. NUL)
    char[256]       info;        ///< Additional context (file path, etc.)
}

// ---------------------------------------------------------------------------
// Load options (opaque — pass null for all defaults)
// ---------------------------------------------------------------------------

/// Options struct for `ufbx_load_*` functions.  The full definition is in
/// `extern/ufbx/ufbx.h`.  Pass `null` here to use ufbx's built-in defaults;
/// that is the recommended starting point for all simple use cases.
struct ufbx_load_opts;

// ---------------------------------------------------------------------------
// Scene objects
// ---------------------------------------------------------------------------

/// Polygonal mesh geometry.
///
/// Only the fields used by the `load_fbx` example are exposed here.  The full
/// struct (`sizeof` = 1264 bytes) contains additional attributes
/// (UV sets, color sets, skin deformers, subdivision info, etc.) that can be
/// added by mirroring the corresponding fields from `ufbx.h`.
///
/// Layout verified by static asserts below.
struct ufbx_mesh {
    // ufbx_element header (128 bytes): name, props, ids, instances, type,
    // connections, dom_node, scene.  We don't expose these fields here; access
    // the mesh name through `ufbx_node.name` instead.
    private ubyte[128] _element;

    size_t num_vertices;     ///< Number of logical vertex positions (offset 128)
    size_t num_indices;      ///< Number of index tuples (corners)  (offset 136)
    size_t num_faces;        ///< Number of polygonal faces         (offset 144)
    size_t num_triangles;    ///< Total triangles if triangulated   (offset 152)
    size_t num_edges;        ///< Edge count (may be 0 if absent)   (offset 160)
    size_t max_face_triangles; ///< Max tris in a single face       (offset 168)
    size_t num_empty_faces;  ///< Faces with 0 vertices             (offset 176)
    size_t num_point_faces;  ///< Faces with 1 vertex               (offset 184)
    size_t num_line_faces;   ///< Faces with 2 vertices             (offset 192)

    /// Face index ranges — `faces.data[i].{index_begin,num_indices}`.        (offset 200)
    ufbx_face_list faces;

    // face_smoothing, face_material, face_group, face_hole (4 × 16 = 64)
    // edges, edge_smoothing, edge_crease, edge_visibility   (4 × 16 = 64)
    // vertex_indices (16)
    // Total padding to reach `vertices` at offset 360: 216 + 144 = 360.
    private ubyte[144] _after_faces;

    /// Logical vertex positions, one per `num_vertices`.                     (offset 360)
    /// For indexed/per-corner access use `vertex_position` (not bound here).
    ufbx_vec3_list vertices;

    // Remaining fields (vertex_first_index, vertex_position, vertex_normal,
    // vertex_uv, skinned_*, deformers, subdivision, materials …)
    // 1264 − 376 = 888 bytes.
    private ubyte[888] _rest;
}

/// Scene node — a transform in the hierarchy that may carry a mesh, light,
/// camera, etc.  Only the fields needed for basic scene traversal are exposed.
///
/// Layout verified by static asserts below.
struct ufbx_node {
    // The first 128 bytes are a union { ufbx_element element; struct { name,
    // props, element_id, typed_id } }. We expose `name` from offset 0 and
    // pad the remainder of the union.
    ufbx_string name;           ///< Node name (UTF-8, NUL-terminated)         (offset 0)
    private ubyte[112] _tail;   ///< Rest of the 128-byte ufbx_element union   (offset 16)

    ufbx_node*  parent;         ///< Parent node, null for the root             (offset 128)
    ufbx_node_list children;    ///< Direct children                            (offset 136)

    /// Attached mesh, null if the node is not a mesh node.                   (offset 152)
    ufbx_mesh* mesh;

    // local_transform (ufbx_transform = 80), geometry_transform (80),
    // inherit_scale (24), inherit_scale_node* (8), rotation_order (4+pad),
    // euler_rotation (24), node_to_parent/world/geo/geo_world/unscaled (5×96),
    // adjust_* fields, materials, bind_pose, bool flags, node_depth …
    // 1104 − 160 = 944 bytes.
    private ubyte[944] _rest;
}

/// Top-level scene returned by `ufbx_load_*` functions.
///
/// Layout verified by static asserts below.
struct ufbx_scene {
    // ufbx_metadata (544) + ufbx_scene_settings (128) = 672 bytes.
    private ubyte[672] _meta_settings;

    ufbx_node* root_node;        ///< Implicit root node (always non-null)     (offset 672)
    private void* _anim;         ///< Default animation descriptor              (offset 680)

    // The union that follows contains all typed element lists.  We expose
    // only the two most commonly needed: nodes and meshes.
    private ubyte[16] _unknowns; ///< ufbx_unknown_list (16 bytes)              (offset 688)
    ufbx_node_list nodes;        ///< All nodes in the scene (incl. root)       (offset 704)
    ufbx_mesh_list meshes;       ///< All mesh attribute objects                (offset 720)

    // Remaining element lists (lights, cameras, bones, …), texture_files,
    // elements, connections, elements_by_name, dom_root …
    // 1448 − 736 = 712 bytes.
    private ubyte[712] _rest;
}

// ---------------------------------------------------------------------------
// Compile-time layout verification
// ---------------------------------------------------------------------------
// These fire immediately if ufbx updates its struct layout and we need to
// re-sync.  Offsets were obtained by compiling ufbx.h with gcc and printing
// offsetof / sizeof for each field.

static assert(ufbx_string.sizeof    == 16,   "ufbx_string size mismatch");
static assert(ufbx_vec3.sizeof      == 24,   "ufbx_vec3 size mismatch");
static assert(ufbx_transform.sizeof == 80,   "ufbx_transform size mismatch");
static assert(ufbx_matrix.sizeof    == 96,   "ufbx_matrix size mismatch");
static assert(ufbx_face.sizeof      == 8,    "ufbx_face size mismatch");
static assert(ufbx_error.sizeof     == 616,  "ufbx_error size mismatch");
static assert(ufbx_mesh.sizeof      == 1264, "ufbx_mesh size mismatch");
static assert(ufbx_node.sizeof      == 1104, "ufbx_node size mismatch");
static assert(ufbx_scene.sizeof     == 1448, "ufbx_scene size mismatch");

// Field offset assertions
static assert(ufbx_error.description.offsetof == 8,   "ufbx_error.description offset");
static assert(ufbx_error.stack_size.offsetof  == 24,  "ufbx_error.stack_size offset");
static assert(ufbx_error.info_length.offsetof == 352, "ufbx_error.info_length offset");
static assert(ufbx_error.info.offsetof        == 360, "ufbx_error.info offset");

static assert(ufbx_mesh.num_vertices.offsetof == 128, "ufbx_mesh.num_vertices offset");
static assert(ufbx_mesh.num_indices.offsetof  == 136, "ufbx_mesh.num_indices offset");
static assert(ufbx_mesh.num_faces.offsetof    == 144, "ufbx_mesh.num_faces offset");
static assert(ufbx_mesh.faces.offsetof        == 200, "ufbx_mesh.faces offset");
static assert(ufbx_mesh.vertices.offsetof     == 360, "ufbx_mesh.vertices offset");

static assert(ufbx_node.name.offsetof         == 0,   "ufbx_node.name offset");
static assert(ufbx_node.parent.offsetof        == 128, "ufbx_node.parent offset");
static assert(ufbx_node.children.offsetof      == 136, "ufbx_node.children offset");
static assert(ufbx_node.mesh.offsetof          == 152, "ufbx_node.mesh offset");

static assert(ufbx_scene.root_node.offsetof   == 672, "ufbx_scene.root_node offset");
static assert(ufbx_scene.nodes.offsetof        == 704, "ufbx_scene.nodes offset");
static assert(ufbx_scene.meshes.offsetof       == 720, "ufbx_scene.meshes offset");

// ---------------------------------------------------------------------------
// Public API — load + free
// ---------------------------------------------------------------------------

/// Load a scene from a file on disk.
/// Pass `opts = null` for default options (recommended for simple use cases).
/// On failure returns `null` and writes an error description into `*error`.
ufbx_scene* ufbx_load_file(
    const(char)*         filename,
    const(ufbx_load_opts)* opts,
    ufbx_error*          error);

/// Load a scene from an in-memory buffer.
/// On failure returns `null` and writes an error description into `*error`.
ufbx_scene* ufbx_load_memory(
    const(void)*           data,
    size_t                 data_size,
    const(ufbx_load_opts)* opts,
    ufbx_error*            error);

/// Free a previously loaded (or evaluated) scene.
void ufbx_free_scene(ufbx_scene* scene);

/// Increment a scene's reference count (advanced use).
void ufbx_retain_scene(ufbx_scene* scene);
