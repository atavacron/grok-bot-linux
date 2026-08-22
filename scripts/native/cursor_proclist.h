#ifndef CURSOR_PROCLIST_H
#define CURSOR_PROCLIST_H

#if defined(__APPLE__) || defined(__linux__)
#include <sys/types.h>
#elif defined(_WIN32)
typedef unsigned int pid_t;
#endif

#include <cstdint>
#include <string>
#include <vector>

struct ProcessInfo {
    pid_t pid;
    pid_t ppid;
    std::string name;
    std::vector<std::string> argv;
    uint64_t cpuTimeMs;
    uint64_t memoryMB;
    std::string extensionId;
    std::string ownerAgentId;
};

bool getProcessInformation(pid_t pid, ProcessInfo& info);
std::vector<pid_t> getDescendantPids(const std::vector<pid_t>& rootPids, bool includeRoot);

struct SystemMemoryInfo {
    uint64_t totalBytes = 0;
    uint64_t availableBytes = 0;
    int pressureLevel = 0;
    bool hasPressureLevel = false;
};

bool getSystemMemoryInfo(SystemMemoryInfo& out);

#endif
