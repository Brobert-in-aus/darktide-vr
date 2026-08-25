add_executable(darktidevr-fingerprint main.cpp)
target_compile_options(darktidevr-fingerprint PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-fingerprint PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-fingerprint PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME fingerprint_help COMMAND darktidevr-fingerprint --help)
  add_test(NAME fingerprint_self
    COMMAND darktidevr-fingerprint --exe $<TARGET_FILE:darktidevr-fingerprint>)
  find_program(DARKTIDEVR_POWERSHELL NAMES pwsh powershell REQUIRED)
  add_test(NAME fingerprint_json_contract
    COMMAND "${DARKTIDEVR_POWERSHELL}" -NoLogo -NoProfile -NonInteractive
      -File "${CMAKE_CURRENT_SOURCE_DIR}/verify-output.ps1"
      -Tool $<TARGET_FILE:darktidevr-fingerprint>)
endif()
