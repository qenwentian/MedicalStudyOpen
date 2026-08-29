#include <iostream>
#include <thread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <cstdint>
#include <cmath>
#include <algorithm>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#endif

// The exactly 32-byte cache-aligned struct
struct alignas(32) BvhNode {
    float min[3];
    int32_t leftChild;
    float max[3];
    int32_t payload;
};

// Global mapped BVH
static BvhNode* g_bvh = nullptr;
static size_t g_num_nodes = 0;

// Thread Pool / Worker Queue State
struct RaycastRequest {
    float physicalX;
    float physicalY;
    void (*callback)(int32_t);
};

static std::queue<RaycastRequest> g_requestQueue;
static std::mutex g_queueMutex;
static std::condition_variable g_queueCV;
static bool g_workerRunning = false;
static std::thread g_workerThread;

extern "C" {
    // Forward declaration for traversing
    int32_t TraverseLBVH(const float origin[3], const float dir[3]);

    // Dummy Thermion integration function for unprojection.
    // In production, this securely wraps `filament::Camera::unproject()`.
    void ThermionUnproject(float physicalX, float physicalY, float outOrigin[3], float outDir[3]) {
        // Mock unprojection for architecture demonstration
        outOrigin[0] = 0.0f; outOrigin[1] = 0.0f; outOrigin[2] = -10.0f;
        outDir[0] = 0.0f; outDir[1] = 0.0f; outDir[2] = 1.0f;
    }

    void BVHWorkerLoop() {
        while (g_workerRunning) {
            RaycastRequest req;
            {
                std::unique_lock<std::mutex> lock(g_queueMutex);
                g_queueCV.wait(lock, [] { return !g_requestQueue.empty() || !g_workerRunning; });
                
                if (!g_workerRunning && g_requestQueue.empty()) break;
                
                req = g_requestQueue.front();
                g_requestQueue.pop();
            }
            
            float origin[3];
            float dir[3];
            ThermionUnproject(req.physicalX, req.physicalY, origin, dir);
            
            int32_t hitMeshKey = TraverseLBVH(origin, dir);
            
            if (req.callback) {
                req.callback(hitMeshKey);
            }
        }
    }

    bool InitBvh(const char* filepath) {
        if (g_bvh) return true; // Already initialized
        
#ifdef _WIN32
        HANDLE hFile = CreateFileA(filepath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (hFile == INVALID_HANDLE_VALUE) return false;
        
        HANDLE hMap = CreateFileMapping(hFile, NULL, PAGE_READONLY, 0, 0, NULL);
        if (!hMap) { CloseHandle(hFile); return false; }
        
        g_bvh = reinterpret_cast<BvhNode*>(MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0));
        
        LARGE_INTEGER size;
        GetFileSizeEx(hFile, &size);
        g_num_nodes = size.QuadPart / sizeof(BvhNode);
#else
        int fd = open(filepath, O_RDONLY);
        if (fd < 0) return false;
        struct stat sb;
        fstat(fd, &sb);
        g_bvh = reinterpret_cast<BvhNode*>(mmap(nullptr, sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0));
        g_num_nodes = sb.st_size / sizeof(BvhNode);
        close(fd);
#endif
        
        // Start the single dedicated worker thread
        if (g_bvh && !g_workerRunning) {
            g_workerRunning = true;
            g_workerThread = std::thread(BVHWorkerLoop);
        }

        return g_bvh != nullptr;
    }

    void ShutdownBvh() {
        if (g_workerRunning) {
            {
                std::lock_guard<std::mutex> lock(g_queueMutex);
                g_workerRunning = false;
            }
            g_queueCV.notify_all();
            if (g_workerThread.joinable()) {
                g_workerThread.join();
            }
        }
    }

    // Slab method for AABB ray intersection
    bool IntersectAABB(const float min[3], const float max[3], const float origin[3], const float invDir[3], float& tMin, float& tMax) {
        float t1 = (min[0] - origin[0]) * invDir[0];
        float t2 = (max[0] - origin[0]) * invDir[0];
        
        tMin = std::min(t1, t2);
        tMax = std::max(t1, t2);
        
        for (int i = 1; i < 3; ++i) {
            t1 = (min[i] - origin[i]) * invDir[i];
            t2 = (max[i] - origin[i]) * invDir[i];
            tMin = std::max(tMin, std::min(t1, t2));
            tMax = std::min(tMax, std::max(t1, t2));
        }
        return tMax >= tMin && tMax >= 0.0f;
    }

    // O(log N) flat array traversal
    int32_t TraverseLBVH(const float origin[3], const float dir[3]) {
        if (!g_bvh || g_num_nodes == 0) return -1;
        
        float invDir[3] = { 1.0f/dir[0], 1.0f/dir[1], 1.0f/dir[2] };
        
        int32_t stack[64];
        int stackPtr = 0;
        stack[stackPtr++] = 0; // Root node index
        
        int32_t closestMesh = -1;
        float closestT = 1e9f;
        
        while (stackPtr > 0) {
            int32_t nodeIdx = stack[--stackPtr];
            const BvhNode& node = g_bvh[nodeIdx];
            
            float tMin, tMax;
            if (IntersectAABB(node.min, node.max, origin, invDir, tMin, tMax)) {
                if (tMin > closestT) continue; // Early exit: obscured
                
                if (node.leftChild < 0) {
                    // Leaf Node
                    closestT = tMin;
                    closestMesh = node.payload;
                } else {
                    // Branch Node - push children
                    stack[stackPtr++] = node.payload;   // right child index
                    stack[stackPtr++] = node.leftChild; // left child index
                }
            }
        }
        return closestMesh;
    }

    // Asynchronous FFI Bridge
    // Safe for NativeCallable.listener marshaling back to Dart.
    // Uses a dedicated worker thread queue to prevent OS thread thrashing.
    void RaycastAsync(float physicalX, float physicalY, void (*callback)(int32_t hitMeshKey)) {
        if (!g_workerRunning) return;
        
        {
            std::lock_guard<std::mutex> lock(g_queueMutex);
            g_requestQueue.push({physicalX, physicalY, callback});
        }
        g_queueCV.notify_one();
    }
}
