#include "../isolated_transports.h"
#include "core/shared_controller_state.h"
#include <process.h>
#include <iostream>

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 2) throw std::runtime_error("Expected child test executable");
    darktidevr::tests::isolate_transports();
    using namespace darktidevr::core;
    SharedControllerStateWriter writer;
    SharedControllerStateReader reader;
    SharedControllerState state{};
    state.sequence = 911;
    state.timestamp_ns = 1234;
    if (!writer.publish(state)) throw std::runtime_error("Fixture publish failed");
    SharedControllerState before{};
    if (!reader.read(before)) throw std::runtime_error("Fixture read failed");
    if (_wspawnl(_P_WAIT, argv[1], argv[1], nullptr) != 0) {
      throw std::runtime_error("Child transport tests failed");
    }
    SharedControllerState after{};
    if (!reader.read(after) || after.sequence != 911 ||
        after.transport_generation != before.transport_generation) {
      throw std::runtime_error("Child test modified its parent's mapping");
    }
    std::cout << "transport_process_isolation=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
