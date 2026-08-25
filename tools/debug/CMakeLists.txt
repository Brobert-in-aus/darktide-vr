add_executable(darktidevr_watch_write watch_write.cpp)
target_compile_options(darktidevr_watch_write PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr_watch_write PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
