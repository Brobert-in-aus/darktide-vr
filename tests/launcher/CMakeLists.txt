if(BUILD_TESTING)
  add_test(NAME launcher_cleanup_continuation COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-cleanup-continuation.ps1")
  set_tests_properties(launcher_cleanup_continuation PROPERTIES TIMEOUT 10 LABELS "launcher")
  add_test(NAME launcher_psykhanium_request
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
      "${CMAKE_CURRENT_SOURCE_DIR}/validate-psykhanium-request.ps1")
  add_test(NAME launcher_game_exit_result
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
      "${CMAKE_CURRENT_SOURCE_DIR}/validate-game-exit-result.ps1")
  set_tests_properties(launcher_game_exit_result PROPERTIES
    LABELS "phase1;launcher" TIMEOUT 25)
  add_test(NAME launcher_startup_focus
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
      "${CMAKE_CURRENT_SOURCE_DIR}/validate-startup-focus.ps1")
  set_tests_properties(launcher_startup_focus PROPERTIES
    LABELS "phase1;launcher" TIMEOUT 20)
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
