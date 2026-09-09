#include "core/xr_math.h"
#include <array>
#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
namespace darktidevr::math {Pose legacy_compose(Pose,Pose);Pose legacy_inverse(Pose);}
using namespace darktidevr::math;
void check(bool v) {if(!v) throw std::runtime_error("pose optimisation mismatch");}
float max_component_error{};
void near(float a,float b,float tolerance) {
  check(std::isfinite(a)&&std::isfinite(b));
  const auto error=std::abs(a-b);max_component_error=(std::max)(max_component_error,error);
  check(error<=tolerance);
}
void compare(Pose a,Pose b) {
  near(a.orientation.x,b.orientation.x,2e-6F);near(a.orientation.y,b.orientation.y,2e-6F);
  near(a.orientation.z,b.orientation.z,2e-6F);near(a.orientation.w,b.orientation.w,2e-6F);
  near(a.position.x,b.position.x,2e-5F);near(a.position.y,b.position.y,2e-5F);near(a.position.z,b.position.z,2e-5F);
}
int main() {
  std::mt19937 random(9042026);
  std::uniform_real_distribution<float> component(-1,1), position(-10,10), exponent(-15,15);
  const auto pose=[&] {
    const auto scale=std::pow(10.0F,exponent(random));
    return Pose{{component(random)*scale,component(random)*scale,component(random)*scale,component(random)*scale},
      {position(random),position(random),position(random)}};
  };
  std::array<Pose,1024> parents,children;
  for(unsigned i=0;i<100000;++i) {
    const auto parent=pose(),child=pose();
    compare(compose(parent,child),legacy_compose(parent,child));
    compare(inverse(parent),legacy_inverse(parent));
    if(i<parents.size()){parents[i]=parent;children[i]=child;}
  }
  for(const float invalid:{0.0F,std::numeric_limits<float>::denorm_min(),std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::max()}) {
    Pose bad{{invalid,0,0,0},{1,2,3}};
    const auto throws=[](auto fn){try{fn();return false;}catch(const std::invalid_argument&){return true;}};
    check(throws([&]{compose(bad,Pose{});})&&throws([&]{legacy_compose(bad,Pose{});}));
    check(throws([&]{compose(Pose{},bad);})&&throws([&]{legacy_compose(Pose{},bad);}));
    check(throws([&]{inverse(bad);})&&throws([&]{legacy_inverse(bad);}));
  }
  double checksum{};
  for(unsigned trial=0;trial<5;++trial) {
    const auto measure=[&](bool old) {
      const auto start=std::chrono::steady_clock::now();double sum{};
      for(unsigned i=0;i<1000000;++i) {
        const auto index=i%parents.size();
        const auto value=old?legacy_compose(parents[index],children[index]):compose(parents[index],children[index]);
        sum+=value.position.x+value.orientation.w;
      }
      checksum+=sum;
      return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    };
    double before{},after{};
    if(trial%2){after=measure(false);before=measure(true);}else{before=measure(true);after=measure(false);}
    std::cout << "trial=" << trial << " compositions=1000000 old_ms=" << before << " new_ms=" << after << '\n';
  }
  std::cout << "PASS samples=100000 max_component_error=" << max_component_error << " checksum=" << checksum << '\n';
}
