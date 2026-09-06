#include "core/aim_stabilization.h"
#include "core/menu_pointer_input.h"
#include "core/panel_pointer.h"
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

using darktidevr::core::AimStabilization;
using darktidevr::math::Quaternion;
namespace {
void check(bool value,const char* message) { if(!value) throw std::runtime_error(message); }
Quaternion yaw(float radians) { return darktidevr::math::from_axis_angle({0,1,0},radians); }
float angle(Quaternion q) { return 2*std::atan2(q.y,q.w); }
void near(float a,float b,float epsilon,const char* message) { check(std::abs(a-b)<epsilon,message); }
}
int main() {
  try {
    AimStabilization filter;
    auto first=filter.update(yaw(0),1,1000000000,1,true);
    check(first.has_value(),"first sample rejected");
    auto moved=filter.update(yaw(0.2F),2,1010000000,1,true);
    check(angle(*moved)>0 && angle(*moved)<0.2F,"step not stabilized");
    auto duplicate=filter.update(yaw(0.2F),2,1010000000,1,true);
    near(angle(*duplicate),angle(*moved),1e-7F,"duplicate advanced state");
    auto reset=filter.update(yaw(1),2,1010000000,2,true);
    near(angle(*reset),1,1e-6F,"epoch did not reset duplicate sequence");
    check(!filter.update(yaw(1),3,1020000000,2,false),"tracking loss accepted");
    near(angle(*filter.update(yaw(-1),4,1030000000,2,true)),-1,1e-6F,"reacquisition blended stale pose");
    near(angle(*filter.update(yaw(1),5,2030000000,2,true)),1,1e-6F,"gap blended stale pose");
    near(angle(*filter.update(yaw(-1),4,2020000000,2,true)),-1,1e-6F,"reordered sample blended");
    check(!filter.update({0,0,0,0},6,2040000000,2,true),"zero quaternion accepted");
    check(!filter.update({0,0,0,std::numeric_limits<float>::quiet_NaN()},7,2050000000,2,true),"NaN accepted");
    check(!filter.update(yaw(0),0,2060000000,2,true),"zero sequence accepted");
    check(!filter.update(yaw(0),8,0,2,true),"invalid time accepted");
    filter.update(yaw(0.1F),1,1000000000,3,true);
    const auto q=yaw(0.1F);
    auto negated=filter.update({-q.x,-q.y,-q.z,-q.w},2,1010000000,3,true);
    near(angle(*negated),0.1F,1e-6F,"quaternion sign caused rotation");
    filter.reset();
    near(angle(*filter.update(yaw(-2),3,1020000000,3,true)),-2,1e-6F,"explicit reset failed");
    bool threw=false;
    try { AimStabilization invalid({0,1,10,0.1}); } catch(const std::invalid_argument&) { threw=true; }
    check(threw,"invalid cutoff accepted");
    // An adaptive filter must reduce lag on a rapid turn compared with beta=0.
    AimStabilization adaptive, fixed({8,0,10,0.1});
    adaptive.update(yaw(0),1,1000000000,1,true); fixed.update(yaw(0),1,1000000000,1,true);
    auto quick=adaptive.update(yaw(1),2,1010000000,1,true);
    auto slow=fixed.update(yaw(1),2,1010000000,1,true);
    check(angle(*quick)>angle(*slow),"speed did not reduce lag");
    // Same elapsed slow motion at several sampling rates: bounded rate variation.
    float results[3]{}; const int rates[3]={60,90,120};
    for(int r=0;r<3;++r) {
      AimStabilization varying;
      for(int i=0;i<=rates[r];++i) {
        const auto t=static_cast<double>(i)/rates[r];
        const auto output=varying.update(yaw(static_cast<float>(t)*0.2F),
          static_cast<std::uint64_t>(i+1),1000000000+static_cast<std::int64_t>(t*1e9),1,true);
        results[r]=angle(*output);
      }
    }
    near(results[0],results[2],0.001F,"sample-rate-dependent slow tracking");
    AimStabilization jitter;
    double raw_energy=0,filtered_energy=0;
    for(int i=0;i<180;++i) {
      const float raw=(i%2==0 ? 0.002F : -0.002F);
      auto output=jitter.update(yaw(raw),static_cast<std::uint64_t>(i+1),
        1000000000+static_cast<std::int64_t>(i)*11111111,1,true);
      if(i>30) { raw_energy+=raw*raw; filtered_energy+=angle(*output)*angle(*output); }
    }
    check(filtered_energy<raw_energy*0.25,"steady angular jitter not reduced");
    // Crossing the +/-pi representation boundary must take the short path.
    AimStabilization seam;
    seam.update(yaw(3.13F),1,1000000000,1,true);
    auto across=seam.update(yaw(-3.13F),2,1010000000,1,true);
    check(std::abs(angle(*across))>3.1F,"wrapped through zero at quaternion seam");
    AimStabilization pointer_filter;
    pointer_filter.update(yaw(0),1,1000000000,1,true);
    const auto pointer_rotation=pointer_filter.update(yaw(0.2F),2,1010000000,1,true);
    const auto hit=darktidevr::core::map_pointer_to_panel(
      {{0,0,0},darktidevr::math::rotate(*pointer_rotation,{0,0,-1})},
      {{0,0,0,1},{0,0,-2}},4,2,1000,500,0,0,1000,500);
    check(hit.has_value(),"filtered ray missed test panel");
    darktidevr::core::MenuPointerInputState buttons;
    darktidevr::core::MenuPointerInput input{};
    input.active=true; input.source_position=std::pair{hit->source_x,hit->source_y};
    buttons.update(input);
    input.trigger=1; input.time_seconds=0.01;
    bool pressed=false;
    for(const auto& event:buttons.update(input)) {
      if(event.type==darktidevr::core::MenuPointerEventType::button_down) {
        pressed=true;
        check(event.source_x==hit->source_x && event.source_y==hit->source_y,"click disagreed with filtered hover");
      }
    }
    check(pressed,"filter delayed trigger edge");
    std::cout << "aim_stabilization=pass ownership resets signs adaptive_speed rates\n";
    return 0;
  } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
