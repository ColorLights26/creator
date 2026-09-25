#include "creator_scene.hpp"
#include "creator_abi.h"
#include <cassert>
#include <cstring>
#include <iostream>

namespace {
class Probe : public creator::Scene {
  float impulse=0;
 public:
  void reset(uint32_t) override { impulse=0; }
  void update(const creator::Frame& f) override {
    for(auto& event:f.music.events[2]) impulse+=event.strength;
  }
  void render(const creator::Frame& f,creator::Canvas& c) const override {
    creator::Paint p;p.color={1,1,1,1};
    c.rect({impulse,float(f.time),f.music.energy,1},p);
  }
};
std::unique_ptr<creator::Scene> make(){return std::make_unique<Probe>();}
template<class T>void put(std::array<uint8_t,520>& b,int offset,T value){std::memcpy(b.data()+offset,&value,sizeof(value));}
std::array<uint8_t,520> signal(int64_t seq,int64_t serial,bool active=true){
  std::array<uint8_t,520>b{};put(b,0,uint32_t(0x32565253));put(b,4,uint16_t(2));put(b,6,uint16_t(5));put(b,8,uint32_t(520));
  put(b,16,int64_t(2));put(b,24,seq);put(b,44,float(.75));
  put(b,472,serial);put(b,488,float(.5));b[493]=active?1:0;return b;
}
std::vector<float> draw(CPInstance* p){assert(cp_draw(p)==1);auto b=cp_commands(p);return {b,b+cp_command_length(p)};}
std::array<float,20> options(){return {1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1};}
}
namespace creator { const std::vector<Program>& installedPrograms(){static std::vector<Program> p={{"probe","test",make,{},{}}};return p;} }
int main(){
  assert(cp_abi_version()==1);assert(cp_create("probe","wrong",42)==nullptr);
  auto p=cp_create("probe","test",42), other=cp_create("probe","test",42);assert(p&&other);auto o=options();
  assert(cp_configure(p,o.data(),20,1,1,0)==1);assert(cp_configure(other,o.data(),20,1,1,0)==1);
  auto b=signal(1,1);assert(cp_consume(p,b.data(),520)==1);assert(cp_consume(p,b.data(),520)==1);
  assert(cp_update(p,320,568,.1,0)==1);auto first=draw(p); // rect path starts at index 19
  assert(first[19]==.5f);assert(first[20]>.09f&&first[20]<.11f);
  assert(cp_update(other,320,568,.1,0)==1);assert(draw(other)[19]==0);
  b=signal(2,1);assert(cp_consume(p,b.data(),520)==1);assert(cp_update(p,320,568,.2,0)==1);assert(draw(p)[19]==.5f);
  // Turning reaction off preserves particle history, but admits no new impulse.
  assert(cp_configure(p,o.data(),20,0,1,.2)==1);b=signal(3,2);assert(cp_consume(p,b.data(),520)==1);
  assert(cp_update(p,320,568,.3,0)==1);auto off=draw(p);assert(off[19]==.5f);
  assert(cp_configure(p,o.data(),20,1,0,.3)==1);assert(cp_update(p,320,568,50,0)==1);auto paused=draw(p);assert(paused[20]==off[20]);
  assert(cp_configure(p,o.data(),20,1,1,50)==1);assert(cp_update(p,320,568,50.1,0)==1);auto resumed=draw(p);assert(resumed[20]<.41f);
  assert(cp_reset(p,42)==1);assert(cp_update(p,320,568,0,0)==1);assert(draw(p)[19]==0);
  b[0]=0;assert(cp_consume(p,b.data(),520)==0);assert(std::strlen(cp_error(p))>0);
  creator::Program def{"probe","test",make,{},{}};
  for(auto bad:std::vector<std::vector<float>>{{2,0},{1,0},{9,1,999},{6,1000},{1,0,2,0,2,0}}){
    bool failed=false;try{creator::validateCommands(bad,def);}catch(const std::exception&){failed=true;}assert(failed);
  }
  cp_destroy(p);cp_destroy(other);std::cout<<"PASS ABI, event deduplication, independent instances, reaction history, pause/reset, malformed commands\n";
}
