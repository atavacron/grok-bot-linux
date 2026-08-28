// N-API bindings for cursor-proclist. Matches the JS wrapper shipped in the
// Windows payload:
//   cursor_proclist_scan_async(roots?: number[]) -> Promise<tuple[]>
//   cursor_proclist_system_memory() -> {totalBytes, availableBytes, pressureLevel?} | null

#include "cursor_proclist.h"

#include <node_api.h>
#include <unistd.h>

#include <memory>
#include <string>
#include <vector>

namespace {

struct ScanRequest {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::vector<pid_t> roots;
  std::vector<ProcessInfo> results;
  bool ok = true;
  std::string error;
};

bool read_roots(napi_env env, napi_callback_info info, std::vector<pid_t>& roots) {
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

  if (argc == 0) {
    roots.push_back(getpid());
    return true;
  }

  napi_valuetype type;
  napi_typeof(env, argv[0], &type);
  if (type == napi_undefined || type == napi_null) {
    roots.push_back(getpid());
    return true;
  }

  bool is_array = false;
  napi_is_array(env, argv[0], &is_array);
  if (!is_array) {
    int64_t v = 0;
    if (napi_get_value_int64(env, argv[0], &v) == napi_ok && v > 0) {
      roots.push_back(static_cast<pid_t>(v));
      return true;
    }
    roots.push_back(getpid());
    return true;
  }

  uint32_t len = 0;
  napi_get_array_length(env, argv[0], &len);
  for (uint32_t i = 0; i < len; ++i) {
    napi_value item;
    napi_get_element(env, argv[0], i, &item);
    int64_t v = 0;
    if (napi_get_value_int64(env, item, &v) == napi_ok && v > 0) {
      roots.push_back(static_cast<pid_t>(v));
    }
  }
  if (roots.empty()) roots.push_back(getpid());
  return true;
}

napi_value tuple_from_info(napi_env env, const ProcessInfo& p) {
  napi_value arr;
  // JS wrapper documents:
  // [pid, ppid, name, extensionId, cpuTimeMs, memoryMB, argv, ownerAgentId, requestId]
  napi_create_array_with_length(env, 9, &arr);

  napi_value v_pid, v_ppid, v_name, v_ext, v_cpu, v_mem, v_argv, v_owner, v_req;
  napi_create_int64(env, p.pid, &v_pid);
  napi_create_int64(env, p.ppid, &v_ppid);
  napi_create_string_utf8(env, p.name.c_str(), NAPI_AUTO_LENGTH, &v_name);
  napi_create_string_utf8(env, p.extensionId.c_str(), NAPI_AUTO_LENGTH, &v_ext);
  // Host sampler does number arithmetic (memSumMb += p). BigInt throws.
  napi_create_int64(env, static_cast<int64_t>(p.cpuTimeMs), &v_cpu);
  napi_create_int64(env, static_cast<int64_t>(p.memoryMB), &v_mem);
  napi_create_string_utf8(env, p.ownerAgentId.c_str(), NAPI_AUTO_LENGTH, &v_owner);
  napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &v_req);

  napi_create_array_with_length(env, p.argv.size(), &v_argv);
  for (size_t i = 0; i < p.argv.size(); ++i) {
    napi_value s;
    napi_create_string_utf8(env, p.argv[i].c_str(), NAPI_AUTO_LENGTH, &s);
    napi_set_element(env, v_argv, static_cast<uint32_t>(i), s);
  }

  napi_set_element(env, arr, 0, v_pid);
  napi_set_element(env, arr, 1, v_ppid);
  napi_set_element(env, arr, 2, v_name);
  napi_set_element(env, arr, 3, v_ext);
  napi_set_element(env, arr, 4, v_cpu);
  napi_set_element(env, arr, 5, v_mem);
  napi_set_element(env, arr, 6, v_argv);
  napi_set_element(env, arr, 7, v_owner);
  napi_set_element(env, arr, 8, v_req);
  return arr;
}

void scan_execute(napi_env, void* data) {
  auto* req = static_cast<ScanRequest*>(data);
  try {
    auto pids = getDescendantPids(req->roots, true);
    req->results.reserve(pids.size());
    for (pid_t pid : pids) {
      ProcessInfo info{};
      if (getProcessInformation(pid, info)) {
        req->results.push_back(std::move(info));
      }
    }
  } catch (const std::exception& ex) {
    req->ok = false;
    req->error = ex.what();
  }
}

void scan_complete(napi_env env, napi_status, void* data) {
  auto* req = static_cast<ScanRequest*>(data);
  if (!req->ok) {
    napi_value err;
    napi_create_string_utf8(env, req->error.c_str(), NAPI_AUTO_LENGTH, &err);
    napi_value error_obj;
    napi_create_error(env, nullptr, err, &error_obj);
    napi_reject_deferred(env, req->deferred, error_obj);
  } else {
    napi_value arr;
    napi_create_array_with_length(env, req->results.size(), &arr);
    for (size_t i = 0; i < req->results.size(); ++i) {
      napi_set_element(env, arr, static_cast<uint32_t>(i), tuple_from_info(env, req->results[i]));
    }
    napi_resolve_deferred(env, req->deferred, arr);
  }
  napi_delete_async_work(env, req->work);
  delete req;
}

napi_value scan_async(napi_env env, napi_callback_info info) {
  auto* req = new ScanRequest();
  read_roots(env, info, req->roots);

  napi_value promise;
  napi_create_promise(env, &req->deferred, &promise);

  napi_value name;
  napi_create_string_utf8(env, "cursor_proclist_scan_async", NAPI_AUTO_LENGTH, &name);
  napi_create_async_work(env, nullptr, name, scan_execute, scan_complete, req, &req->work);
  napi_queue_async_work(env, req->work);
  return promise;
}

napi_value system_memory(napi_env env, napi_callback_info) {
  SystemMemoryInfo mem{};
  if (!getSystemMemoryInfo(mem)) {
    napi_value n;
    napi_get_null(env, &n);
    return n;
  }
  napi_value obj;
  napi_create_object(env, &obj);
  napi_value total, avail;
  napi_create_bigint_uint64(env, mem.totalBytes, &total);
  napi_create_bigint_uint64(env, mem.availableBytes, &avail);
  napi_set_named_property(env, obj, "totalBytes", total);
  napi_set_named_property(env, obj, "availableBytes", avail);
  if (mem.hasPressureLevel) {
    napi_value pressure;
    napi_create_int32(env, mem.pressureLevel, &pressure);
    napi_set_named_property(env, obj, "pressureLevel", pressure);
  }
  return obj;
}

napi_value init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"cursor_proclist_scan_async", nullptr, scan_async, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"cursor_proclist_system_memory", nullptr, system_memory, nullptr, nullptr, nullptr,
       napi_default, nullptr},
  };
  napi_define_properties(env, exports, 2, desc);
  return exports;
}

}  // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, init)
