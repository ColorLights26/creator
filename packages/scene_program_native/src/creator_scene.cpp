#include "creator_scene.hpp"
#include "creator_abi.h"
#include <chrono>
#include <cstring>
#include <cstdlib>
#include <limits>

namespace creator {
Color Color::argb(uint32_t v) { return {float((v>>16)&255)/255, float((v>>8)&255)/255, float(v&255)/255, float(v>>24)/255}; }
Color Color::opacity(float v) const { return {r,g,b,v}; }
uint32_t Random::next() { state_ ^= state_<<13; state_ ^= state_>>17; state_ ^= state_<<5; return state_; }
float Random::unit() { return float(next()>>8) / 16777216.0f; }
Path& Path::moveTo(float x,float y) { data_.insert(data_.end(),{0,x,y}); return *this; }
Path& Path::lineTo(float x,float y) { data_.insert(data_.end(),{1,x,y}); return *this; }
Path& Path::quadraticTo(float a,float b,float x,float y) { data_.insert(data_.end(),{2,a,b,x,y}); return *this; }
Path& Path::cubicTo(float a,float b,float c,float d,float x,float y) { data_.insert(data_.end(),{3,a,b,c,d,x,y}); return *this; }
Path& Path::close() { data_.push_back(4); return *this; }
Path& Path::rect(Rect r) { return moveTo(r.x,r.y).lineTo(r.x+r.width,r.y).lineTo(r.x+r.width,r.y+r.height).lineTo(r.x,r.y+r.height).close(); }
Path& Path::circle(Vec2 c,float r) {
  constexpr float k=.552284749831f;
  return moveTo(c.x+r,c.y).cubicTo(c.x+r,c.y+k*r,c.x+k*r,c.y+r,c.x,c.y+r)
    .cubicTo(c.x-k*r,c.y+r,c.x-r,c.y+k*r,c.x-r,c.y)
    .cubicTo(c.x-r,c.y-k*r,c.x-k*r,c.y-r,c.x,c.y-r)
    .cubicTo(c.x+k*r,c.y-r,c.x+r,c.y-k*r,c.x+r,c.y).close();
}
Paint Paint::linear(Vec2 a,Vec2 b,std::vector<Color> c,std::vector<float> s) {
  Paint p; p.gradient=1; p.geometry={a.x,a.y,b.x,b.y}; p.colors=std::move(c); p.stops=std::move(s);
  if(p.stops.empty() && p.colors.size()>1) for(size_t i=0;i<p.colors.size();++i) p.stops.push_back(float(i)/float(p.colors.size()-1));
  return p;
}
Paint Paint::radial(Vec2 c,float r,std::vector<Color> colors,std::vector<float> stops) {
  auto p=linear(c,{r,0},std::move(colors),std::move(stops)); p.gradient=2; return p;
}
static void require(bool ok,const char* error) { if(!ok) throw std::runtime_error(error); }
static void color(std::vector<float>& out,Color c) { out.insert(out.end(),{c.r,c.g,c.b,c.a}); }
static void paint(std::vector<float>& out,const Paint& p) {
  require(p.gradient>=0 && p.gradient<=2,"Unknown gradient");
  require(p.gradient==0 || (p.colors.size()>=2 && p.colors.size()<=8 && p.colors.size()==p.stops.size()),"Gradient needs 2..8 matching colors/stops");
  color(out,p.color); out.insert(out.end(),{float(p.blend),p.strokeWidth,float(p.strokeCap),float(p.strokeJoin),float(p.gradient)});
  out.insert(out.end(),p.geometry.begin(),p.geometry.end()); out.push_back(float(p.gradient ? p.colors.size() : 0));
  if(p.gradient) for(size_t i=0;i<p.colors.size();++i) { color(out,p.colors[i]); out.push_back(p.stops[i]); }
}
static void pathData(std::vector<float>& out,const Path& p) {
  out.insert(out.end(),{float(p.fillRule),float(p.data().size())}); out.insert(out.end(),p.data().begin(),p.data().end());
}
static float resource(const std::vector<std::string>& all,const std::string& name) {
  auto i=std::find(all.begin(),all.end(),name); if(i==all.end()) throw std::runtime_error("Unknown resource: "+name); return float(i-all.begin());
}
Canvas::Canvas(std::vector<float>& b,const std::vector<std::string>& m,const std::vector<std::string>& i):buffer_(b),materials_(m),images_(i){buffer_.clear();}
void Canvas::emit(int op,const std::vector<float>& p) {
  require(buffer_.size()+p.size()+2<=262144,"Drawing command budget exceeded (1 MiB)");
  buffer_.push_back(float(op)); buffer_.push_back(float(p.size())); buffer_.insert(buffer_.end(),p.begin(),p.end());
}
void Canvas::save(){require(depth_<64,"Drawing stack exceeds 64");emit(1,{});++depth_;}
void Canvas::restore(){require(depth_>0,"restore without save/saveLayer");emit(2,{});--depth_;}
void Canvas::saveLayer(float a,Blend b){require(depth_<64,"Drawing stack exceeds 64");emit(3,{a,float(b)});++depth_;}
void Canvas::transform(float a,float b,float c,float d,float x,float y){emit(4,{a,b,c,d,x,y});}
void Canvas::translate(float x,float y){transform(1,0,0,1,x,y);}
void Canvas::scale(float x,float y){transform(x,0,0,y,0,0);}
void Canvas::rotate(float r){transform(std::cos(r),std::sin(r),-std::sin(r),std::cos(r),0,0);}
void Canvas::clip(const Path& p){std::vector<float> b;pathData(b,p);emit(5,b);}
void Canvas::path(const Path& p,const Paint& v){std::vector<float> b;paint(b,v);pathData(b,p);emit(6,b);}
void Canvas::rect(Rect r,const Paint& p){Path v;v.rect(r);path(v,p);}
void Canvas::circle(Vec2 c,float r,const Paint& p){require(r>=0,"Negative radius");Path v;v.circle(c,r);path(v,p);}
void Canvas::points(const std::vector<Vec2>& v,float r,const Paint& p){
  require(v.size()<=32768 && r>=0,"Invalid point batch");std::vector<float>b;paint(b,p);b.push_back(r);b.push_back(float(v.size()));
  for(auto x:v)b.insert(b.end(),{x.x,x.y});emit(7,b);
}
void Canvas::image(const std::string& n,Rect r,float a,Blend b){emit(8,{resource(images_,n),r.x,r.y,r.width,r.height,a,float(b)});}
void Canvas::material(const std::string& n,Rect r,const std::vector<float>& u,const std::vector<std::string>& imgs,Blend mode){
  require(u.size()<=1024 && imgs.size()<=16,"Material parameter budget exceeded");
  std::vector<float>b={resource(materials_,n),r.x,r.y,r.width,r.height,float(mode),float(u.size())};b.insert(b.end(),u.begin(),u.end());
  b.push_back(float(imgs.size()));for(auto& s:imgs)b.push_back(resource(images_,s));emit(9,b);
}
void Canvas::finish()const{require(depth_==0,"Unclosed save/saveLayer");}

// Validate at the producer boundary, before either renderer can dereference it.
void validateCommands(const std::vector<float>& b,const Program& program){
  require(b.size()<=262144,"Command buffer too large");
  for(auto v:b)require(std::isfinite(v),"Non-finite drawing value");
  size_t i=0;int depth=0;
  auto integer=[](float v,int lo,int hi){require(v==std::floor(v)&&v>=lo&&v<=hi,"Invalid command integer");return int(v);};
  auto range=[](float v,float lo,float hi){require(v>=lo&&v<=hi,"Drawing value out of range");};
  while(i<b.size()){
    require(i+2<=b.size(),"Truncated command");int op=integer(b[i++],1,9);size_t n=integer(b[i++],0,262144);require(n<=b.size()-i,"Truncated payload");size_t end=i+n;
    auto take=[&](){require(i<end,"Truncated field");return b[i++];};
    auto col=[&](){for(int c=0;c<4;++c)range(take(),0,1);};
    auto pth=[&](){integer(take(),0,1);size_t count=integer(take(),0,262144);require(count<=end-i,"Truncated path");size_t stop=i+count;while(i<stop){int verb=integer(b[i++],0,4);size_t args=verb==4?0:verb==3?6:verb==2?4:2;require(args<=stop-i,"Truncated path verb");i+=args;}};
    auto pnt=[&](){col();integer(take(),0,2);range(take(),0,8192);integer(take(),0,2);integer(take(),0,2);int kind=integer(take(),0,2);for(int g=0;g<4;++g)take();int stops=integer(take(),0,8);require(kind==0?stops==0:stops>=2,"Invalid gradient");float previous=-1;for(int s=0;s<stops;++s){col();float t=take();range(t,0,1);require(t>=previous,"Unsorted gradient stops");previous=t;}};
    switch(op){
      case 1:require(++depth<=64,"Stack budget");break;
      case 2:require(--depth>=0,"Stack underflow");break;
      case 3:require(++depth<=64,"Stack budget");range(take(),0,1);integer(take(),0,2);break;
      case 4:for(int a=0;a<6;++a)take();break;
      case 5:pth();break;
      case 6:pnt();pth();break;
      case 7:{pnt();range(take(),0,8192);int count=integer(take(),0,32768);for(int p=0;p<count*2;++p)take();break;}
      case 8:integer(take(),0,int(program.images.size())-1);take();take();range(take(),0,8192);range(take(),0,8192);range(take(),0,1);integer(take(),0,2);break;
      case 9:{integer(take(),0,int(program.materials.size())-1);take();take();range(take(),0,8192);range(take(),0,8192);integer(take(),0,2);int count=integer(take(),0,1024);for(int u=0;u<count;++u)take();count=integer(take(),0,16);for(int t=0;t<count;++t)integer(take(),0,int(program.images.size())-1);break;}
    }
    require(i==end,"Trailing command data");
  }
  require(depth==0,"Unclosed drawing stack");
}
} // namespace creator

struct CPInstance {
  const creator::Program* definition;
  std::unique_ptr<creator::Scene> scene;
  creator::Frame frame;
  creator::Music latest;
  std::array<std::vector<creator::Event>,4> pending;
  std::array<int64_t,4> serials{{-1,-1,-1,-1}};
  int64_t session=-1, sequence=-1;
  bool playing=false, reactive=true, hasHost=false;
  double host=0, updateMicros=0;
  std::vector<float> commands;
  std::string error;
};
namespace {
thread_local std::string creationError;
template<class F> int32_t protect(CPInstance* p,F action){
  if(!p)return 0;
  try{action();p->error.clear();return 1;}catch(const std::exception& e){p->error=e.what();p->commands.clear();return 0;}catch(...){p->error="Unknown native scene failure";p->commands.clear();return 0;}
}
template<class T>T read(const uint8_t* b,size_t o){T v;std::memcpy(&v,b+o,sizeof(v));return v;}
const creator::Program* lookup(const char* name){if(!name)return nullptr;for(auto& p:creator::installedPrograms())if(std::strcmp(name,p.id)==0)return &p;return nullptr;}
void clearEvents(CPInstance* p){for(auto& e:p->pending)e.clear();for(auto& e:p->frame.music.events)e.clear();}
}
uint32_t cp_abi_version(){return 1;}
void* cp_allocate(size_t size){return size<=16*1024*1024?std::calloc(1,size):nullptr;}
void cp_free(void* p){std::free(p);}
const char* cp_program_hash(const char* p){auto d=lookup(p);return d?d->hash:nullptr;}
CPInstance* cp_create(const char* name,const char* hash,uint32_t seed){
  try{auto d=lookup(name);creator::require(d&&hash&&std::strcmp(d->hash,hash)==0,"Compiled program/asset mismatch; stop and rebuild");
    auto p=std::make_unique<CPInstance>();p->definition=d;p->scene=d->create();creator::require(bool(p->scene),"Scene factory failed");
    p->frame.seed=seed;p->scene->reset(seed);creationError.clear();return p.release();
  }catch(const std::exception& e){creationError=e.what();return nullptr;}catch(...){creationError="Scene creation failed";return nullptr;}
}
void cp_destroy(CPInstance* p){delete p;}
const char* cp_error(CPInstance* p){return p?p->error.c_str():creationError.c_str();}
int32_t cp_reset(CPInstance* p,uint32_t seed){return protect(p,[&]{p->scene->reset(seed);p->frame.seed=seed;p->frame.time=0;p->frame.delta=0;p->frame.music={};p->latest={};p->hasHost=false;p->session=-1;p->sequence=-1;p->serials.fill(-1);clearEvents(p);p->commands.clear();});}
int32_t cp_configure(CPInstance* p,const float* o,uint32_t count,int32_t reactive,int32_t playing,double host){return protect(p,[&]{
  creator::require(o&&count==20&&std::isfinite(host)&&host>=0,"Invalid frame configuration");
  for(int i=0;i<20;++i)creator::require(std::isfinite(o[i])&&o[i]>=0&&o[i]<=(i<4?2:1),"Invalid options");
  creator::require(o[2]>=.25,"Invalid detail");p->frame.intensity=o[0];p->frame.speed=o[1];p->frame.detail=o[2];p->frame.glow=o[3];
  for(int i=0;i<4;++i)p->frame.colors[i]={o[4+4*i],o[5+4*i],o[6+4*i],o[7+4*i]};
  if(p->playing!=bool(playing)){p->host=host;p->hasHost=true;clearEvents(p);}if(p->reactive!=bool(reactive)){clearEvents(p);p->latest={};p->frame.music={};}
  p->reactive=reactive;p->playing=playing;
});}
int32_t cp_consume(CPInstance* p,const uint8_t* b,uint32_t size){return protect(p,[&]{
  creator::require(b&&size==520&&read<uint32_t>(b,0)==0x32565253&&read<uint16_t>(b,4)==2&&read<uint32_t>(b,8)==520&&read<uint32_t>(b,12)==0,"Invalid canonical signal header");
  auto flags=read<uint16_t>(b,6);creator::require((flags&~15)==0,"Unknown signal flags");
  auto session=read<int64_t>(b,16),seq=read<int64_t>(b,24);creator::require(session>=0&&seq>=0&&read<int64_t>(b,32)>=0,"Invalid signal clock");
  creator::Music next;for(int i=0;i<96;++i)creator::require(std::isfinite(read<float>(b,40+i*4)),"Non-finite signal");
  std::array<creator::Event,4> events;std::array<bool,4> active;
  for(int i=0;i<4;++i){auto o=424+i*24;events[i]={read<int64_t>(b,o),read<int64_t>(b,o+8),read<float>(b,o+16),int(b[o+20])};active[i]=b[o+21]==1;
    creator::require(events[i].serial>=0&&events[i].timestampMicros>=0&&std::isfinite(events[i].strength)&&b[o+20]<=4&&b[o+21]<=1&&read<uint16_t>(b,o+22)==0,"Invalid signal event");}
  if(p->session==session&&seq<=p->sequence)return;
  if(p->session!=session){p->serials.fill(-1);clearEvents(p);p->session=session;}p->sequence=seq;
  next.active=(flags&5)==5;
  if(next.active){for(int i=0;i<6;++i)next.dynamics[i]=read<float>(b,40+i*4);next.energy=next.dynamics[1];
    next.bass=read<float>(b,64);next.body=read<float>(b,68);next.spark=read<float>(b,72);next.flow=read<float>(b,76);
    for(int i=0;i<31;++i){next.spectrum[i]=read<float>(b,108+i*4);next.smoothSpectrum[i]=read<float>(b,232+i*4);}
    next.bpm=read<float>(b,380);next.phase=read<float>(b,384);
  }else clearEvents(p);
  for(int i=0;i<4;++i)if(active[i]&&events[i].serial>p->serials[i]){
    p->serials[i]=events[i].serial;
    if(next.active&&p->reactive&&p->playing){creator::require(p->pending[i].size()<256,"Pending music event budget exceeded");p->pending[i].push_back(events[i]);}
  }
  p->latest=std::move(next);
});}
int32_t cp_update(CPInstance* p,double w,double h,double host,int32_t reduced){return protect(p,[&]{
  creator::require(std::isfinite(w)&&std::isfinite(h)&&w>0&&h>0&&w<=8192&&h<=8192&&std::isfinite(host)&&host>=0,"Invalid scene viewport/time");
  auto begin=std::chrono::steady_clock::now();auto& f=p->frame;f.width=float(w);f.height=float(h);f.reducedMotion=reduced;
  f.delta=p->playing&&p->hasHost?std::clamp(host-p->host,0.0,.25)*(reduced?.1:1):0;p->host=host;p->hasHost=true;f.time+=f.delta;
  f.music=p->playing&&p->reactive?p->latest:creator::Music{};
  if(f.music.active&&!reduced)f.music.events=p->pending;for(auto& events:p->pending)events.clear();
  if(p->playing)p->scene->update(f);
  p->updateMicros=std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-begin).count();
});}
int32_t cp_draw(CPInstance* p){return protect(p,[&]{creator::Canvas canvas(p->commands,p->definition->materials,p->definition->images);p->scene->render(p->frame,canvas);canvas.finish();creator::validateCommands(p->commands,*p->definition);});}
const float* cp_commands(CPInstance* p){return p?p->commands.data():nullptr;}
uint32_t cp_command_length(CPInstance* p){return p?uint32_t(p->commands.size()):0;}
double cp_update_micros(CPInstance* p){return p?p->updateMicros:0;}
