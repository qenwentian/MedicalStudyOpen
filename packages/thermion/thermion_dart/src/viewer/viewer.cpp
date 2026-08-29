#include <filament/View.h>
#include <filament/Engine.h>
#include <utils/Entity.h>
#include <utils/EntityManager.h>

extern "C" {

// C-linkable FFI hook exported to Dart
void thermion_viewer_pick(filament::View* view, int x, int y, void(*callback)(const char*)) {
    
    // Filament's multi-threaded pick API
    view->pick(x, y, [callback](filament::View::PickingQueryResult const& result) {
        
        // This lambda is executed by Filament's Render Thread!
        filament::Engine* engine = filament::Engine::getInstance(); // simplified
        auto& tcm = engine->getTransformManager();
        auto& ncm = utils::EntityManager::get().getNameManager(); // Hypothetical NameComponentManager
        
        if (result.renderable) {
            // Retrieve the original string name we set in process_anatomy.py
            const char* entityName = ncm.getName(result.renderable);
            
            // Invoke the Dart NativeCallable.listener
            // This safely crosses the thread boundary back to the Dart isolate!
            callback(entityName);
        } else {
            callback(""); // No hit
        }
    });
}

} // extern "C"
