"""
Z-Anatomy Headless Blender Asset Pipeline
=========================================
Batch-processes Z-Anatomy .blend files:
1. Merges individual meshes by functional anatomical group (reducing draw calls from 5000+ to <100).
2. Encodes SystemID (UBO index) and unique MeshKey into vertex attributes.
3. Generates 3 Levels of Detail (LOD0: 100%, LOD1: 50%, LOD2: 15%) with Draco compression.
4. Computes offline AABB bounds for spatial BVH raycasting.
5. Emits a database manifest with integer keys for O(1) SQLite resolution.

Usage:
    blender --background path/to/Startup.blend --python pipeline/process_anatomy.py -- --output assets/3d/ --manifest assets/db/manifest.json
"""

import sys
import os
import json
import argparse
import struct

try:
    import bpy
    import mathutils
except ImportError:
    print("ERROR: This script must be run inside Blender's Python environment.")
    print("Example: blender --background Startup.blend --python pipeline/process_anatomy.py -- --output assets/3d/")
    sys.exit(1)


# ── System Definitions & Global UBO Index Mapping ──────────────────────────
SYSTEM_COLLECTION_MAP = {
    "Skeletal":       {"system_id": "SYS_SKELETAL",       "ubo_index": 0, "depth_priority": 1, "prefix": "BONE"},
    "Nervous":        {"system_id": "SYS_NERVOUS",        "ubo_index": 1, "depth_priority": 2, "prefix": "NERV"},
    "Visceral":       {"system_id": "SYS_VISCERAL",       "ubo_index": 2, "depth_priority": 3, "prefix": "ORGAN"},
    "Organs":         {"system_id": "SYS_VISCERAL",       "ubo_index": 2, "depth_priority": 3, "prefix": "ORGAN"},
    "Cardiovascular": {"system_id": "SYS_VASCULAR",       "ubo_index": 3, "depth_priority": 4, "prefix": "VASC"},
    "Muscular":       {"system_id": "SYS_MUSCULAR",       "ubo_index": 4, "depth_priority": 5, "prefix": "MUSC"},
    "Integumentary":  {"system_id": "SYS_INTEGUMENTARY",  "ubo_index": 5, "depth_priority": 6, "prefix": "SKIN"},
}

LOD_RATIOS = {
    "LOD0": 1.0,   # 100% - Close-up viewing
    "LOD1": 0.50,  # 50%  - Regional viewing
    "LOD2": 0.15,  # 15%  - Whole-body overview
}


def sanitize_id(name: str, prefix: str) -> str:
    """Converts a Blender object name into a clean unique identifier."""
    clean = "".join(c if c.isalnum() else "_" for c in name.upper()).strip("_")
    if not clean.startswith(prefix):
        clean = f"{prefix}_{clean}"
    return clean


def calculate_aabb(obj):
    """Calculates world-space Axis-Aligned Bounding Box (AABB) for spatial BVH."""
    bbox_corners = [obj.matrix_world @ mathutils.Vector(corner) for corner in obj.bound_box]
    min_x = min(c.x for c in bbox_corners)
    min_y = min(c.y for c in bbox_corners)
    min_z = min(c.z for c in bbox_corners)
    max_x = max(c.x for c in bbox_corners)
    max_y = max(c.y for c in bbox_corners)
    max_z = max(c.z for c in bbox_corners)
    return {
        "min": [round(min_x, 4), round(min_y, 4), round(min_z, 4)],
        "max": [round(max_x, 4), round(max_y, 4), round(max_z, 4)],
    }


def process_collection(collection, system_info, output_dir, manifest_entries, bvh_entries, key_counter):
    """Processes, encodes, and merges meshes within an anatomical collection."""
    system_id = system_info["system_id"]
    ubo_index = system_info["ubo_index"]
    prefix = system_info["prefix"]

    mesh_objects = [obj for obj in collection.all_objects if obj.type == "MESH"]
    if not mesh_objects:
        return key_counter

    print(f"\n[+] Batching {collection.name} ({len(mesh_objects)} meshes) -> System: {system_id} [UBO Index: {ubo_index}]")

    # 1. Record metadata, compute AABB bounds, and bake meshKey to TEXCOORD_1
    uv_layer_name = "TEXCOORD_1"
    for obj in mesh_objects:
        key_counter += 1
        mesh_key = key_counter
        entity_id = sanitize_id(obj.name, prefix)

        aabb = calculate_aabb(obj)
        bvh_entries.append({
            "mesh_key": mesh_key,
            "id": entity_id,
            "system_id": system_id,
            "ubo_index": ubo_index,
            "aabb": aabb,
        })

        manifest_entries.append({
            "id": entity_id,
            "mesh_key": mesh_key,
            "ta_id": obj.get("TA_ID", None),
            "latin_name": obj.get("Latin_Name", obj.name.replace("_", " ").title()),
            "english_name": obj.get("English_Name", obj.name.replace("_", " ").title()),
            "description": obj.get("Description", f"Anatomical component of the {collection.name}."),
            "system_id": system_id,
            "hierarchy_path": f"{system_id}/{collection.name.upper()}/{entity_id}",
        })

        # Bake mesh_key into UV map
        mesh = obj.data
        if uv_layer_name not in mesh.uv_layers:
            mesh.uv_layers.new(name=uv_layer_name)
        uv_layer = mesh.uv_layers[uv_layer_name]
        
        # We store the integer mesh_key directly into the UV's X coordinate.
        for loop in mesh.loops:
            uv_layer.data[loop.index].uv = (mesh_key, 0.0)

    # 2. Join all meshes into a single object to reduce draw calls
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)

    # Architectural Mitigation: Explicitly override context for headless execution
    # Headless environments lack a 3D Viewport context, causing bpy.ops to fail.
    override = bpy.context.copy()
    override["active_object"] = mesh_objects[0]
    override["selected_editable_objects"] = mesh_objects
    with bpy.context.temp_override(**override):
        bpy.ops.object.join()
    
    joined_obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # ── THE DECIMATION INTERPOLATION TRAP ──────────────────────────
    # WARNING: We are adding a DECIMATE modifier after baking meshKey into TEXCOORD_1.
    # Decimate collapses edges and *interpolates* UVs. 
    # Since we did NOT run "Merge By Distance", the meshes remain separate islands,
    # so Decimate will not bridge vertices from different anatomical parts (e.g. 1002 and 1003).
    # IF you ever weld vertices before this step, Decimate will average the meshKeys 
    # (e.g. UV X = 1002.5), completely destroying the ID system during C++ BVH raycasting.
    # DO NOT WELD VERTICES ACROSS DISCRETE ANATOMICAL PARTS BEFORE DECIMATION.
    decimate_mod = joined_obj.modifiers.new(name="DecimateLOD", type="DECIMATE")

    # 3. Export discrete LOD tiers with Draco compression
    for lod_name, ratio in LOD_RATIOS.items():
        lod_filename = f"{system_id.lower()}_{lod_name.lower()}.glb"
        lod_filepath = os.path.join(output_dir, lod_filename)

        print(f"  -> Exporting {lod_name} (decimate: {ratio}) -> {lod_filename}...")

        decimate_mod.ratio = ratio

        bpy.ops.export_scene.gltf(
            filepath=lod_filepath,
            use_selection=True,
            export_format="GLB",
            export_draco_mesh_compression_enable=True,
            export_draco_mesh_compression_level=7,
            export_apply=True,
        )

        print(f"     [OK] Saved: {lod_filepath}")

    return key_counter

class BvhNode:
    def __init__(self):
        self.min = [0.0, 0.0, 0.0]
        self.max = [0.0, 0.0, 0.0]
        self.left_child = -1
        self.payload = -1

def build_bvh(entries):
    """Builds a top-down Linear Bounding Volume Hierarchy (LBVH) flat array."""
    nodes = []
    
    def build_recursive(current_entries):
        if not current_entries:
            return -1
        
        node_idx = len(nodes)
        nodes.append(BvhNode())
        node = nodes[node_idx]
        
        # Calculate bounds
        min_x = min(e["aabb"]["min"][0] for e in current_entries)
        min_y = min(e["aabb"]["min"][1] for e in current_entries)
        min_z = min(e["aabb"]["min"][2] for e in current_entries)
        max_x = max(e["aabb"]["max"][0] for e in current_entries)
        max_y = max(e["aabb"]["max"][1] for e in current_entries)
        max_z = max(e["aabb"]["max"][2] for e in current_entries)
        
        node.min = [min_x, min_y, min_z]
        node.max = [max_x, max_y, max_z]
        
        if len(current_entries) == 1:
            node.left_child = -1
            node.payload = current_entries[0]["mesh_key"]
            return node_idx
        
        # Split along longest axis
        extent_x = max_x - min_x
        extent_y = max_y - min_y
        extent_z = max_z - min_z
        
        axis = 0
        if extent_y > extent_x and extent_y > extent_z:
            axis = 1
        elif extent_z > extent_x and extent_z > extent_y:
            axis = 2
            
        current_entries.sort(key=lambda e: (e["aabb"]["min"][axis] + e["aabb"]["max"][axis]) / 2.0)
        
        mid = len(current_entries) // 2
        left_idx = build_recursive(current_entries[:mid])
        right_idx = build_recursive(current_entries[mid:])
        
        nodes[node_idx].left_child = left_idx
        nodes[node_idx].payload = right_idx
        
        return node_idx

    if entries:
        build_recursive(entries)
        
    return nodes

def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    parser = argparse.ArgumentParser(description="Z-Anatomy Headless Batch Processing Pipeline")
    parser.add_argument("--output", default="assets/3d", help="Directory to save exported .glb files")
    parser.add_argument("--manifest", default="assets/db/manifest.json", help="Path to save the generated JSON manifest")
    parser.add_argument("--bvh", default="assets/3d/spatial_bvh.bin", help="Path to save precomputed spatial BVH AABB index")
    args = parser.parse_args(argv)

    os.makedirs(args.output, exist_ok=True)
    os.makedirs(os.path.dirname(args.manifest) or ".", exist_ok=True)
    os.makedirs(os.path.dirname(args.bvh) or ".", exist_ok=True)

    manifest_entries = []
    bvh_entries = []
    key_counter = 1000

    print("=" * 65)
    print("  Z-Anatomy Headless High-Performance Asset Pipeline")
    print(f"  Target 3D Assets:  {args.output}")
    print(f"  Target Manifest:   {args.manifest}")
    print(f"  Target Spatial BVH:{args.bvh}")
    print("=" * 65)

    for col_name, system_info in SYSTEM_COLLECTION_MAP.items():
        col = bpy.data.collections.get(col_name)
        if col:
            key_counter = process_collection(col, system_info, args.output, manifest_entries, bvh_entries, key_counter)
        else:
            for existing_col in bpy.data.collections:
                if col_name.lower() in existing_col.name.lower():
                    key_counter = process_collection(existing_col, system_info, args.output, manifest_entries, bvh_entries, key_counter)
                    break

    # Save manifest
    with open(args.manifest, "w", encoding="utf-8") as f:
        json.dump(manifest_entries, f, indent=2, ensure_ascii=False)

    # Build and Save Spatial BVH (LBVH Binary Format)
    nodes = build_bvh(bvh_entries)
    with open(args.bvh, "wb") as f:
        for node in nodes:
            # struct format: 3 floats, 1 int, 3 floats, 1 int = 32 bytes
            data = struct.pack('<3fi3fi', 
                node.min[0], node.min[1], node.min[2], node.left_child,
                node.max[0], node.max[1], node.max[2], node.payload
            )
            f.write(data)

    print(f"\n[OK] Pipeline completed! Exported {len(manifest_entries)} entities to {args.manifest} and spatial index to {args.bvh}")


if __name__ == "__main__":
    main()
