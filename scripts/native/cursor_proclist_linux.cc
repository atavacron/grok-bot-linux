// Linux /proc implementation of cursor-proclist.
// The Windows installer ships the public header and JS wrapper, but strips the
// platform .cc files. This file reconstructs the Linux side from that header
// contract so the module can be rebuilt against Electron on GNU/Linux.

#include "cursor_proclist.h"

#include <dirent.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <queue>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace {

constexpr size_t kMaxScanPids = 4096;

std::string read_file(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return {};
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

std::string read_env_value(pid_t pid, const char* key) {
  std::string raw = read_file("/proc/" + std::to_string(pid) + "/environ");
  if (raw.empty()) return {};
  const std::string prefix = std::string(key) + "=";
  size_t start = 0;
  while (start < raw.size()) {
    size_t end = raw.find('\0', start);
    if (end == std::string::npos) end = raw.size();
    if (raw.compare(start, prefix.size(), prefix) == 0) {
      return raw.substr(start + prefix.size(), end - start - prefix.size());
    }
    start = end + 1;
  }
  return {};
}

bool parse_stat(pid_t pid, pid_t& ppid, uint64_t& cpu_time_ms, std::string& comm) {
  std::string path = "/proc/" + std::to_string(pid) + "/stat";
  std::string text = read_file(path);
  if (text.empty()) return false;

  // comm is wrapped in parentheses and may contain spaces.
  auto lparen = text.find('(');
  auto rparen = text.rfind(')');
  if (lparen == std::string::npos || rparen == std::string::npos || rparen <= lparen) {
    return false;
  }
  comm = text.substr(lparen + 1, rparen - lparen - 1);

  std::istringstream rest(text.substr(rparen + 2));
  std::string state;
  unsigned long utime = 0, stime = 0;
  int ppid_i = 0;
  rest >> state >> ppid_i;
  // fields 5..13 unused here, 14=utime, 15=stime
  unsigned long skip;
  for (int i = 0; i < 9; ++i) rest >> skip;
  rest >> utime >> stime;
  ppid = static_cast<pid_t>(ppid_i);

  long ticks = sysconf(_SC_CLK_TCK);
  if (ticks <= 0) ticks = 100;
  cpu_time_ms = static_cast<uint64_t>((utime + stime) * 1000ULL / static_cast<unsigned long>(ticks));
  return true;
}

uint64_t rss_mb(pid_t pid) {
  std::string status = read_file("/proc/" + std::to_string(pid) + "/status");
  std::istringstream in(status);
  std::string line;
  while (std::getline(in, line)) {
    if (line.rfind("VmRSS:", 0) == 0) {
      unsigned long kb = 0;
      std::sscanf(line.c_str(), "VmRSS: %lu", &kb);
      return kb / 1024ULL;
    }
  }
  return 0;
}

std::vector<std::string> read_argv(pid_t pid) {
  std::string raw = read_file("/proc/" + std::to_string(pid) + "/cmdline");
  std::vector<std::string> argv;
  size_t start = 0;
  while (start < raw.size()) {
    size_t end = raw.find('\0', start);
    if (end == std::string::npos) end = raw.size();
    if (end > start) argv.emplace_back(raw.substr(start, end - start));
    start = end + 1;
  }
  return argv;
}

std::unordered_map<pid_t, pid_t> snapshot_parents() {
  std::unordered_map<pid_t, pid_t> parent;
  DIR* dir = opendir("/proc");
  if (!dir) return parent;
  while (dirent* ent = readdir(dir)) {
    if (ent->d_name[0] == '\0' || !std::isdigit(static_cast<unsigned char>(ent->d_name[0]))) {
      continue;
    }
    pid_t pid = static_cast<pid_t>(std::atoi(ent->d_name));
    pid_t ppid = 0;
    uint64_t cpu = 0;
    std::string comm;
    if (parse_stat(pid, ppid, cpu, comm)) {
      parent[pid] = ppid;
    }
  }
  closedir(dir);
  return parent;
}

}  // namespace

bool getProcessInformation(pid_t pid, ProcessInfo& info) {
  pid_t ppid = 0;
  uint64_t cpu_ms = 0;
  std::string comm;
  if (!parse_stat(pid, ppid, cpu_ms, comm)) return false;

  info.pid = pid;
  info.ppid = ppid;
  info.name = comm;
  info.argv = read_argv(pid);
  info.cpuTimeMs = cpu_ms;
  info.memoryMB = rss_mb(pid);
  info.extensionId = read_env_value(pid, "CURSOR_SPAWNED_BY_EXTENSION_ID");
  info.ownerAgentId = read_env_value(pid, "CURSOR_CONVERSATION_ID");
  return true;
}

std::vector<pid_t> getDescendantPids(const std::vector<pid_t>& rootPids, bool includeRoot) {
  auto parent = snapshot_parents();
  std::unordered_map<pid_t, std::vector<pid_t>> children;
  children.reserve(parent.size());
  for (const auto& kv : parent) {
    children[kv.second].push_back(kv.first);
  }

  std::vector<pid_t> out;
  std::unordered_set<pid_t> seen;
  std::queue<pid_t> q;

  for (pid_t root : rootPids) {
    if (root <= 0) continue;
    if (includeRoot && seen.insert(root).second) out.push_back(root);
    q.push(root);
  }

  while (!q.empty() && out.size() < kMaxScanPids) {
    pid_t cur = q.front();
    q.pop();
    auto it = children.find(cur);
    if (it == children.end()) continue;
    for (pid_t child : it->second) {
      if (seen.insert(child).second) {
        out.push_back(child);
        q.push(child);
      }
      if (out.size() >= kMaxScanPids) break;
    }
  }
  return out;
}

bool getSystemMemoryInfo(SystemMemoryInfo&) {
  // Header contract: Linux callers use /proc/meminfo from JS. Return false.
  return false;
}
