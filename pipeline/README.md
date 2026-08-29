# Z-Anatomy Asset Processing Pipeline

Automated headless Python pipeline using Blender's native Python API (`bpy`) to batch-process, decimate, and export Z-Anatomy `.blend` models into mobile-optimized, Draco-compressed `.glb` files with 3 Levels of Detail (LOD0, LOD1, LOD2).

---

## Prerequisites

1. **Blender 3.6+** installed on your system.
2. Z-Anatomy `.blend` source files downloaded from:
   - [Zenodo Open Repository](https://zenodo.org/records/4959223) (`Z-Anatomy.zip`)
   - Or [moueza/Z-Anatomy GitHub](https://github.com/moueza/Z-Anatomy)

---

## Running the Pipeline

Execute the pipeline in headless mode (`--background`) from your terminal:

```bash
# Windows
blender --background "path\to\Startup.blend" --python pipeline\process_anatomy.py -- --output assets\3d\ --manifest assets\db\manifest.json

# macOS / Linux
blender --background "/path/to/Startup.blend" --python pipeline/process_anatomy.py -- --output assets/3d/ --manifest assets/db/manifest.json
```

---

## Output Structure

The script outputs:
1. **Draco-compressed `.glb` files** in `assets/3d/`:
   - `sys_skeletal_lod0.glb` (100% detail - close-up view)
   - `sys_skeletal_lod1.glb` (50% detail - regional view)
   - `sys_skeletal_lod2.glb` (15% detail - full-body overview)
   - `sys_muscular_lod0.glb`, `sys_visceral_lod0.glb`, etc.

2. **JSON Manifest** in `assets/db/manifest.json`:
   - Maps every mesh ID (e.g., `BONE_FEMUR_L`) to its English name, Latin name, Terminologia Anatomica code, and parent system.
   - Ingested directly by `DatabaseService.batchInsertEntities()` in Flutter.
