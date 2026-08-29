#include <iostream>
#include <cstdint>
#include <fcntl.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

// The exactly 32-byte cache-aligned struct
struct alignas(32) BvhNode {
    float min[3];
    int32_t leftChild;
    float max[3];
    int32_t payload;
};

int main(int argc, char** argv) {
    if (sizeof(BvhNode) != 32) {
        std::cerr << "Alignment failure! Size is " << sizeof(BvhNode) << " bytes instead of 32." << std::endl;
        return 1;
    }
    std::cout << "[OK] BvhNode size is strictly 32 bytes." << std::endl;

    const char* filename = "test_bvh.bin";

#ifdef _WIN32
    HANDLE hFile = CreateFileA(filename, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }

    HANDLE hMap = CreateFileMapping(hFile, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!hMap) {
        std::cerr << "Failed to create file mapping." << std::endl;
        CloseHandle(hFile);
        return 1;
    }

    void* mapped_ptr = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0);
    if (!mapped_ptr) {
        std::cerr << "Failed to map view of file." << std::endl;
        CloseHandle(hMap);
        CloseHandle(hFile);
        return 1;
    }
    
    // Get file size
    LARGE_INTEGER fileSize;
    GetFileSizeEx(hFile, &fileSize);
    size_t num_nodes = fileSize.QuadPart / sizeof(BvhNode);
#else
    int fd = open(filename, O_RDONLY);
    if (fd < 0) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }
    
    struct stat sb;
    fstat(fd, &sb);
    size_t num_nodes = sb.st_size / sizeof(BvhNode);

    void* mapped_ptr = mmap(nullptr, sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (mapped_ptr == MAP_FAILED) {
        std::cerr << "mmap failed." << std::endl;
        close(fd);
        return 1;
    }
#endif

    BvhNode* bvh = reinterpret_cast<BvhNode*>(mapped_ptr);

    std::cout << "Successfully mapped " << num_nodes << " nodes." << std::endl;
    
    // Print the root node and some children
    for (size_t i = 0; i < num_nodes; ++i) {
        std::cout << "Node " << i << ":\n";
        std::cout << "  Min: [" << bvh[i].min[0] << ", " << bvh[i].min[1] << ", " << bvh[i].min[2] << "]\n";
        std::cout << "  Max: [" << bvh[i].max[0] << ", " << bvh[i].max[1] << ", " << bvh[i].max[2] << "]\n";
        std::cout << "  LeftChild: " << bvh[i].leftChild << "\n";
        std::cout << "  Payload: " << bvh[i].payload << "\n";
    }

#ifdef _WIN32
    UnmapViewOfFile(mapped_ptr);
    CloseHandle(hMap);
    CloseHandle(hFile);
#else
    munmap(mapped_ptr, sb.st_size);
    close(fd);
#endif

    return 0;
}
