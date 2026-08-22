{
  "targets": [
    {
      "target_name": "cursor_proclist",
      "sources": [
        "src/cursor_proclist.cc",
        "src/cursor_proclist_linux.cc"
      ],
      "include_dirs": [
        "src"
      ],
      "cflags_cc": [
        "-std=c++17",
        "-fexceptions",
        "-fno-strict-aliasing"
      ],
      "defines": [
        "NAPI_VERSION=8"
      ]
    }
  ]
}
