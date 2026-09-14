add_executable(darktidevr-settings-backup-tests main.cpp)
target_compile_options(darktidevr-settings-backup-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-settings-backup-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-settings-backup-tests PRIVATE
  darktidevr_core)
add_test(NAME settings_backup
  COMMAND darktidevr-settings-backup-tests)
set_tests_properties(settings_backup PROPERTIES
  LABELS "phase1;settings")
