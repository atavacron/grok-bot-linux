// Minimal N-API stand-in for the private @anysphere/tree-chunk-napi crate.
// The Windows payload only ships tree-chunk-napi.win32-x64-msvc.node. There is
// no public Linux binary or source. host-main.cjs requires this package at
// module load, so we register empty constructors under the names the generated
// loader re-exports. Code-chunking features that call into the real crate will
// fail later; the host process can still start.

#include <node_api.h>

static napi_value EmptyCtor(napi_env env, napi_callback_info info) {
  napi_value this_arg = nullptr;
  napi_get_cb_info(env, info, nullptr, nullptr, &this_arg, nullptr);
  return this_arg;
}

static napi_value DefineEmptyClass(napi_env env, const char* name) {
  napi_value ctor = nullptr;
  napi_define_class(env, name, NAPI_AUTO_LENGTH, EmptyCtor, nullptr, 0, nullptr, &ctor);
  return ctor;
}

static napi_value Init(napi_env env, napi_value exports) {
  const char* names[] = {
      "Chunk",
      "ChunkerRouter",
      "CompressedFileOutline",
      "FileTree",
      "PartialFileContext",
  };
  for (const char* name : names) {
    napi_value ctor = DefineEmptyClass(env, name);
    napi_set_named_property(env, exports, name, ctor);
  }
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
