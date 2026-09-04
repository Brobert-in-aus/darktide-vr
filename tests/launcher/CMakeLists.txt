if(BUILD_TESTING)
  add_test(NAME launcher_play_transition
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
      "${CMAKE_CURRENT_SOURCE_DIR}/validate-play-transition.ps1")
  set_tests_properties(launcher_play_transition PROPERTIES
    LABELS "phase1;launcher" TIMEOUT 20)
endif()

if(BUILD_TESTING)
  add_test(NAME validate-early-failure COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-early-failure.ps1")
endif()
