// Red Neuronal Cuántica — Puerto fiel de Visuales Inmersivas v02.
// Plexo sináptico interconectado con potenciales de acción en cascada,
// halos bioluminiscentes e impulsos reactivos al audio.
// Música: la energía tensa la red hacia el centro y dispara más impulsos.
// Pulso elige qué marca el ritmo: Golpes lanza una onda de activación que
// recorre la red desde el centro y hace destellar las sinapsis en cada golpe;
// Graves hincha los nodos y engruesa los enlaces con los graves; Agudos hace
// centellear los nodos y chisporrotear los impulsos con los agudos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, la red deriva tranquila exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: hasta dónde llega cada sinapsis: constelación suelta o red tupida.
  CreatorModifier.slider('alcance', 'Alcance sináptico', min: 60, max: 170, value: 110),
  // MOVIMIENTO: nodos que derivan rectos o una red que ondula como algas.
  CreatorModifier.slider('oleaje', 'Oleaje', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: sin halo, el halo de siempre o una bruma bioluminiscente.
  CreatorModifier.slider('halo', 'Halo bioluminiscente', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Constelación', {
    'alcance': 65,
    'halo': 2.2,
    'pulso': 'Agudos',
  }),
  CreatorVariation('Marea Neural', {
    'alcance': 150,
    'oleaje': 1,
    'halo': .5,
    'pulso': 'Graves',
    'speed': .8,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Node { float x, y, vx, vy, size, energy; };
  struct Pulse { int from, to; float prog, speed; int colIdx; };
  std::vector<Node> nodes;
  std::vector<Pulse> pulses;
  int done = 0;
  float fenergy = 0.0f, fbass = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Onda de activación del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj propio del oleaje y del centelleo (igual a 30 y 60 FPS).
  double flow = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void step(float w, float h, float reach) {
    const float dt = 1.0f / 60.0f;
    for (size_t i = 0; i < nodes.size(); i++) {
      auto& n = nodes[i];
      n.x += n.vx * dt * 60.0f;
      n.y += n.vy * dt * 60.0f;

      if (n.x <= 0.02f) { n.x = 0.02f; n.vx = std::abs(n.vx); }
      if (n.x >= 0.98f) { n.x = 0.98f; n.vx = -std::abs(n.vx); }
      if (n.y <= 0.02f) { n.y = 0.02f; n.vy = std::abs(n.vy); }
      if (n.y >= 0.98f) { n.y = 0.98f; n.vy = -std::abs(n.vy); }

      // Suave atracción hacia el centro pulsante con la música
      float dx = 0.5f - n.x, dy = 0.5f - n.y;
      float d2 = dx * dx + dy * dy;
      if (d2 > 0.001f) {
        float inv = 1.0f / std::sqrt(d2);
        float pull = 0.00008f * (1.0f + fenergy * 2.0f);
        n.vx += dx * inv * pull;
        n.vy += dy * inv * pull;
      }
      n.energy = std::clamp(n.energy * 0.992f, 0.15f, 1.0f);
    }

    // Progreso de pulsos (potenciales de acción)
    for (size_t i = 0; i < pulses.size();) {
      pulses[i].prog += pulses[i].speed;
      if (pulses[i].prog >= 1.0f) {
        if (pulses[i].to < int(nodes.size())) {
          nodes[pulses[i].to].energy = std::min(1.0f, nodes[pulses[i].to].energy + 0.35f);
        }
        pulses.erase(pulses.begin() + i);
      } else {
        i++;
      }
    }

    // Disparos periódicos o rítmicos de nuevos pulsos: reposo en silencio (máx 6), activo con música (máx 24)
    // Alcance sináptico: los impulsos viajan sólo por enlaces que se dibujan.
    size_t maxPulses = fenergy > 0.05f ? 24 : 6;
    if (pulses.size() < maxPulses && !nodes.empty()) {
      int from = (done * 7) % int(nodes.size());
      float fx = nodes[from].x * w, fy = nodes[from].y * h;
      for (size_t to = 0; to < nodes.size(); to++) {
        if (int(to) == from) continue;
        float tx = nodes[to].x * w, ty = nodes[to].y * h;
        float ddx = tx - fx, ddy = ty - fy;
        if (ddx * ddx + ddy * ddy < (reach * reach)) {
          pulses.push_back({from, int(to), 0.0f, 0.03f + (from % 3) * 0.015f, from % 2});
          break;
        }
      }
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    nodes.clear(); nodes.reserve(65);
    pulses.clear(); pulses.reserve(32);
    done = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    flow = 0.0;
    for (int i = 0; i < 65; i++) {
      float a = rng.unit() * 6.2831853f;
      float spd = 0.0006f + rng.unit() * 0.0010f;
      nodes.push_back({
        rng.unit(), rng.unit(),
        std::cos(a) * spd, std::sin(a) * spd,
        2.2f + rng.unit() * 2.8f,
        0.3f + rng.unit() * 0.7f
      });
    }
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    fenergy = f.music.active ? f.music.energy : 0.0f;
    fbass = f.music.active ? f.music.bass : 0.0f;
    float rate = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) {
      step(f.width, f.height, m.alcance);
      guard++;
    }

    // Bloque de música estándar: graves, medios, agudos, energía y golpe.
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Cada golpe nuevo lanza una onda de activación desde el centro.
    waveAge = std::min(waveAge + dt, 100.0f);
    if (fresh) {
      waveAge = 0.0f;
      wavePower = hit;
    }
    flow += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 1.6f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float clock = float(std::fmod(flow, 1000.0));
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};

    // Fondo radial profundo
    Paint bg = Paint::radial(center, std::max(w, h) * 0.75f,
      {Color::argb(0xff06101e), Color::argb(0xff02060b), Color::argb(0xff000000)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Alcance sináptico: 110 px es la red de siempre.
    const float reach = g.alcance;
    const float connDistSq = reach * reach;

    // Oleaje: la red ondula como algas en una corriente (0 = nodos en su sitio).
    const float sway = g.oleaje * std::min(w, h) * 0.045f;
    std::vector<Vec2> pos(nodes.size());
    for (size_t i = 0; i < nodes.size(); i++) {
      pos[i] = {nodes[i].x * w, nodes[i].y * h};
      if (sway > 0.0f) {
        pos[i].x += sway * std::sin(nodes[i].y * 7.0f + clock * 1.3f);
        pos[i].y += sway * 0.8f * std::cos(nodes[i].x * 6.0f + clock * 1.1f);
      }
    }

    // Resplandor local de la red: Golpes lo enciende de golpe y Graves lo hace respirar.
    const float burst = std::min(0.55f, (golpe * 0.45f + grave * 0.22f) * f.glow);
    if (burst > 0.003f) {
      const float R = std::min(w, h) * 0.6f;
      Paint gl = Paint::radial(center, R,
        {Color{0.0f, 0.95f, 0.85f, burst}, Color{0.1f, 0.4f, 1.0f, burst * 0.5f}, Color{0.0f, 0.2f, 0.6f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    // Golpes y Graves: las sinapsis destellan con cada golpe y engruesan con los graves.
    const float linkLift = 1.0f + golpe * 1.0f + grave * 0.4f;
    const float linkThick = 1.0f + grave * 0.6f + golpe * 1.2f;

    // Dibujar enlaces sinápticos agrupados
    for (size_t i = 0; i < nodes.size(); i++) {
      float x1 = pos[i].x, y1 = pos[i].y;
      for (size_t j = i + 1; j < nodes.size(); j++) {
        float x2 = pos[j].x, y2 = pos[j].y;
        float dx = x2 - x1, dy = y2 - y1;
        float d2 = dx * dx + dy * dy;
        if (d2 < connDistSq) {
          float dist = std::sqrt(d2);
          float alpha = std::clamp((1.0f - dist / reach) * 0.65f * f.intensity * linkLift, 0.0f, 1.0f);
          // Agudos: cada enlace parpadea a su ritmo.
          if (agudo > 0.003f) {
            alpha = std::min(1.0f, alpha * (1.0f + agudo * 0.9f * std::max(0.0f, std::sin(clock * 19.0f + float(i) * 1.3f + float(j) * 0.7f))));
          }
          float combE = (nodes[i].energy + nodes[j].energy) * 0.5f;

          // Lerp entre azul profundo {0, 0.33, 1} y cian neón {0, 1, 0.84}
          Color lcol{
            0.0f,
            0.33f * (1.0f - combE) + 1.0f * combE,
            1.0f * (1.0f - combE) + 0.84f * combE,
            alpha
          };
          Paint lp; lp.blend = Blend::plus; lp.color = lcol;
          lp.strokeWidth = std::max(0.6f, 0.8f + combE * 1.2f) * linkThick;
          Path line; line.moveTo(x1, y1); line.lineTo(x2, y2);
          c.path(line, lp);
        }
      }
    }

    // Dibujar potenciales de acción (pulsos de señal)
    for (const auto& p : pulses) {
      if (p.from >= int(nodes.size()) || p.to >= int(nodes.size())) continue;
      float sx = pos[p.from].x, sy = pos[p.from].y;
      float ex = pos[p.to].x, ey = pos[p.to].y;
      float px = sx + (ex - sx) * p.prog;
      float py = sy + (ey - sy) * p.prog;

      Color pcol = (p.colIdx == 0)
        ? Color{0.0f, 1.0f, 0.88f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)}
        : Color{0.55f, 0.15f, 1.0f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)};
      Paint pp; pp.blend = Blend::plus; pp.color = pcol;
      c.circle({px, py}, 2.8f, pp);

      // Halo del pulso: Agudos lo hace chisporrotear.
      float sizzle = 1.0f;
      float halA = 0.35f * f.intensity;
      if (agudo > 0.003f) {
        const float flick = 0.5f + 0.5f * std::sin(clock * 23.0f + p.prog * 9.0f + float(p.from) * 1.7f);
        sizzle += agudo * 0.9f * flick;
        halA += agudo * 0.3f * flick;
      }
      Paint ph; ph.blend = Blend::plus;
      ph.color = {pcol.r, pcol.g, pcol.b, std::clamp(halA, 0.0f, 1.0f)};
      c.circle({px, py}, 6.5f * sizzle, ph);
    }

    // Dibujar nodos sinápticos (núcleo y halo)
    // Halo bioluminiscente: hasta 1 escala el halo de siempre; más allá suma bruma.
    const float haloSize = std::min(g.halo, 1.0f);
    const float bloom = std::max(0.0f, g.halo - 1.0f);
    const float front = waveAge * std::max(w, h);
    const float band = 0.08f * std::max(w, h);
    for (size_t i = 0; i < nodes.size(); i++) {
      const auto& n = nodes[i];
      Vec2 at = pos[i];
      // Golpes: pop general y la onda de activación que cruza la red.
      float boost = golpe * 0.5f;
      if (onda > 0.003f) {
        const float ddx = at.x - center.x, ddy = at.y - center.y;
        const float off = (std::sqrt(ddx * ddx + ddy * ddy) - front) / band;
        boost += onda * std::exp(-off * off);
      }
      // Agudos: cada nodo centellea a su ritmo.
      float twinkle = 0.0f;
      if (agudo > 0.003f) {
        twinkle = agudo * std::max(0.0f, std::sin(clock * 15.0f + float(i) * 2.4f));
      }
      float rad = n.size * (1.0f + n.energy * 0.45f) * (1.0f + grave * 0.12f + boost * 0.2f);

      // Halo
      Paint glow; glow.blend = Blend::plus;
      glow.color = {0.0f, 0.95f, 0.85f, std::clamp((0.2f + n.energy * 0.35f) * f.intensity * haloSize * (1.0f + grave * 0.8f) + boost * 0.4f, 0.0f, 1.0f)};
      c.circle(at, rad * 2.3f * haloSize * (1.0f + boost * 0.5f + grave * 0.3f), glow);
      if (bloom > 0.0f) {
        Paint soft = Paint::radial(at, rad * (2.3f + bloom * 5.5f),
          {{0.0f, 0.95f, 0.85f, std::clamp((0.12f + n.energy * 0.2f) * bloom * f.intensity, 0.0f, 0.6f)}, {0, 0, 0, 0}},
          {0.0f, 1.0f});
        soft.blend = Blend::plus;
        c.circle(at, rad * (2.3f + bloom * 5.5f), soft);
      }

      // Núcleo
      Paint core; core.blend = Blend::plus;
      core.color = {
        0.1f * (1.0f - n.energy) + 1.0f * n.energy,
        0.75f * (1.0f - n.energy) + 1.0f * n.energy,
        0.95f * (1.0f - n.energy) + 1.0f * n.energy,
        std::clamp((0.7f + n.energy * 0.3f) * f.intensity + boost * 0.5f + twinkle * 0.8f, 0.0f, 1.0f)
      };
      c.circle(at, rad * (1.0f + twinkle * 0.7f), core);
    }
  }
};
''';
