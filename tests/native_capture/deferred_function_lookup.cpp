#include "producer/deferred_function_lookup.h"
#include <stdexcept>
using Lookup = darktidevr::producer::DeferredFunctionLookup;
void require(bool value) { if (!value) throw std::runtime_error("deferred lookup contract"); }
int main() {
  int target{};
  unsigned calls{};
  Lookup lookup;
  auto delayed = [&]() -> Lookup::Result {
    ++calls;
    if (calls == 1) return {1,&target}; // Failed query's pointer is not valid.
    if (calls == 2) return {0,nullptr};
    return {0,&target};
  };
  require(!lookup.resolve(1000,delayed));
  require(!lookup.resolve(999,delayed));
  require(!lookup.resolve(1999,delayed));
  require(calls == 1);
  require(!lookup.resolve(2000,delayed));
  require(lookup.resolve(3000,delayed) == &target);
  require(lookup.resolve(4000,delayed) == &target && calls == 3);
  Lookup exhausted;
  unsigned failures{};
  for (unsigned i=0;i<100;++i)
    require(!exhausted.resolve(i*1000ULL,[&]() -> Lookup::Result { ++failures; return {1,nullptr}; }));
  require(failures == 8 && exhausted.attempts() == 8);
}
