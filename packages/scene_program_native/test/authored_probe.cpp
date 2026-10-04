#include "creator_scene.hpp"
#include "creator_abi.h"
#include <cassert>
#include <cstring>
#include <iostream>

std::vector<float> replay(const creator::Program& program, int fps, bool interleaved=false, const std::vector<float>* modifiers=nullptr) {
  auto p=cp_create(program.id,program.hash,42);
  if(!p)throw std::runtime_error(cp_error(nullptr));
  auto other=interleaved?cp_create(program.id,program.hash,42):nullptr;
  std::vector<float> options={1,1,1,1,.02f,.03f,.08f,1,.2f,.6f,1,1,1,.2f,.6f,1,1,.8f,.5f,1};
  if(modifiers)options.insert(options.end(),modifiers->begin(),modifiers->end());
  const auto count=uint32_t(options.size());
  try {
    if(interleaved&&!other)throw std::runtime_error(cp_error(nullptr));
    if(cp_configure(p,options.data(),count,1,1,0)!=1)throw std::runtime_error(cp_error(p));
    if(other&&cp_configure(other,options.data(),count,1,1,0)!=1)throw std::runtime_error(cp_error(other));
    for(int i=0;i<=fps*4;i++) {
      if(cp_update(p,320,568,double(i)/fps,0)!=1||cp_draw(p)!=1)throw std::runtime_error(cp_error(p));
      if(other&&(cp_update(other,320,568,double(i)/fps,0)!=1||cp_draw(other)!=1))throw std::runtime_error(cp_error(other));
    }
    const auto data=cp_commands(p);std::vector<float> output(data,data+cp_command_length(p));cp_destroy(other);cp_destroy(p);return output;
  }catch(...){cp_destroy(other);cp_destroy(p);throw;}
}
int main(){
  try {
    for(auto& program:creator::installedPrograms()) {
      auto a=replay(program,30),b=replay(program,30),c=replay(program,60);
      if(a.empty()||a!=b||c.empty())throw std::runtime_error("Non-repeatable/empty authored scene");
      if(a!=replay(program,30,true))throw std::runtime_error("Authored instances share mutable state");
      if(a.size()!=c.size())throw std::runtime_error("Ambient geometry changes with frame rate");
      // Four seconds without events: positions and angles should advance by
      // elapsed time, not by callback count. Allow floating point integration.
      for(size_t i=0;i<a.size();++i)
        if(std::abs(a[i]-c[i])>.1f)throw std::runtime_error("Ambient velocity differs at 30/60 FPS");
      // Declared modifiers: 20 floats mean their initial values; any other
      // count, or a value that is not a finite number, is refused.
      const auto& defaults=program.modifiers;
      if(!defaults.empty()&&a!=replay(program,30,false,&defaults))
        throw std::runtime_error("Explicit initial modifiers differ from the defaults");
      std::vector<float> wrong(21+defaults.size(),1);
      auto probe=cp_create(program.id,program.hash,42);
      if(!probe)throw std::runtime_error(cp_error(nullptr));
      const bool extra=cp_configure(probe,wrong.data(),uint32_t(wrong.size()),1,1,0)==1;
      bool invalid=false;
      if(!defaults.empty()){wrong.resize(20+defaults.size());wrong[20]=std::nanf("");invalid=cp_configure(probe,wrong.data(),uint32_t(wrong.size()),1,1,0)==1;}
      cp_destroy(probe);
      if(extra||invalid)throw std::runtime_error("Modifier values outside the declaration were accepted");
      std::cout<<"PASS authored CPU "<<program.id<<": independent instances, repeatable state, 30/60 FPS, "<<a.size()*4<<" command bytes\n";
    }
  }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
