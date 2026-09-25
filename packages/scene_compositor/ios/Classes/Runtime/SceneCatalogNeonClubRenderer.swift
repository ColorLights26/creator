import Foundation
import CoreGraphics
import Metal

struct SceneCatalogNeonClubFrame {
  let logicalWidth: Double
  let logicalHeight: Double
  let time: Double
  let paletteIndex: Int
  let manualIntensity: Double
  let motion: Double
  let lasersEnabled: Bool
  let particlesEnabled: Bool
  let spectrumEnabled: Bool
  let subBass: Double
  let bass: Double
  let lowMid: Double
  let mid: Double
  let highMid: Double
  let treble: Double
  let air: Double
  let energy: Double
  let brightness: Double
  let accentStrength: Double
  let flashStrength: Double
  let spectrum: [Double]
}

@available(iOS 15.0, *)
final class SceneCatalogNeonClubRenderer {
  private let renderer: SceneCatalogVectorRenderer
  var lastStatistics: SceneCatalogVectorRenderer.Statistics? { renderer.lastStatistics }
  var retainedIntermediateBytes: Int { renderer.retainedIntermediateBytes }
  var maximumObservedIntermediateBytes: Int { renderer.maximumObservedIntermediateBytes }
  init(device: MTLDevice) throws {
    renderer = try SceneCatalogVectorRenderer(device: device)
  }
  func render(
    frame: SceneCatalogNeonClubFrame, width: Int, height: Int,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    let scalars = [frame.logicalWidth, frame.logicalHeight, frame.time, frame.manualIntensity,
                   frame.motion, frame.subBass, frame.bass, frame.lowMid, frame.mid, frame.highMid,
                   frame.treble, frame.air, frame.energy, frame.brightness, frame.accentStrength, frame.flashStrength]
    guard scalars.allSatisfy({ $0.isFinite }), frame.spectrum.allSatisfy({ $0.isFinite }),
          frame.logicalWidth > 0, frame.logicalHeight > 0, (0..<4).contains(frame.paletteIndex) else {
      throw NSError(domain: "SceneCatalogNeonClubRenderer", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "neon_club_frame_invalid"])
    }
    let canvas = SceneCatalogVectorCanvas()
    SceneCatalogNeonClubPainter(frame: frame).paint(
      canvas, SceneCatalogVectorSize(frame.logicalWidth, frame.logicalHeight)
    )
    return try renderer.render(
      canvas: canvas, logicalWidth: frame.logicalWidth, logicalHeight: frame.logicalHeight,
      width: width, height: height, outputAllocator: outputAllocator
    )
  }
}

private typealias Canvas = SceneCatalogVectorCanvas
private typealias Size = SceneCatalogVectorSize
private typealias Offset = SceneCatalogVectorOffset
private typealias Rect = SceneCatalogVectorRect
private typealias RRect = SceneCatalogVectorRRect
private typealias Radius = SceneCatalogVectorRadius
private typealias Path = SceneCatalogVectorPath
private typealias Color = SceneCatalogVectorColor
private typealias Colors = SceneCatalogVectorColors
private typealias Paint = SceneCatalogVectorPaint
private typealias Alignment = SceneCatalogVectorAlignment
private typealias LinearGradient = SceneCatalogVectorLinearGradient
private typealias RadialGradient = SceneCatalogVectorRadialGradient
private typealias MaskFilter = SceneCatalogVectorMaskFilter
private typealias BlurStyle = SceneCatalogVectorBlurStyle
private typealias PaintingStyle = SceneCatalogVectorPaintingStyle
private typealias StrokeCap = SceneCatalogVectorStrokeCap
private typealias StrokeJoin = SceneCatalogVectorStrokeJoin
private typealias BlendMode = SceneCatalogVectorBlendMode

private func neonApply<T: AnyObject>(_ value: T, _ action: (T) -> Void) -> T {
  action(value)
  return value
}
private func neonClamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
  min(upper, max(lower, value))
}
private func neonModulo(_ value: Double, _ divisor: Double) -> Double {
  let remainder = value.truncatingRemainder(dividingBy: divisor)
  return remainder < 0 ? remainder + abs(divisor) : remainder
}

// BEGIN GENERATED NEON CLUB PAINTER
// AST-translated by tool/generate_neon_club_painter.dart. Preserve original equations.
private final class SceneCatalogNeonClubPainter {
  let frame: SceneCatalogNeonClubFrame
  init(frame: SceneCatalogNeonClubFrame) { self.frame = frame }
  var time: Double { frame.time }
  var motion: Double { frame.motion }
  var manualIntensity: Double { frame.manualIntensity }
  var lasersEnabled: Bool { frame.lasersEnabled }
  var particlesEnabled: Bool { frame.particlesEnabled }
  var spectrumEnabled: Bool { frame.spectrumEnabled }
  var palette: [Color] { Self.palettes[frame.paletteIndex % Self.palettes.count] }
  static let palettes: [[Color]] = [
    [Color(0xFFFF2BD6), Color(0xFF00E7FF), Color(0xFF7CFF4F)],
    [Color(0xFF00FFB2), Color(0xFF1677FF), Color(0xFFFFF15A)],
    [Color(0xFFFF3D4D), Color(0xFF9B5CFF), Color(0xFF35E7FF)],
    [Color(0xFFFFF6EA), Color(0xFF4CC9FF), Color(0xFFFF2D95)]
  ]
  struct ParticleSeed { let x: Double; let y: Double; let speed: Double; let phase: Double }
  static let particles: [ParticleSeed] = [
    .init(x: 0.0050380230712653296, y: 0.41422036777274795, speed: 1.6250979860132924, phase: 1.3157231233086488),
    .init(x: 0.8437693884606668, y: 0.9691870736666565, speed: 1.2890961749234995, phase: 0.4871562209515965),
    .init(x: 0.16260517072720837, y: 0.1477883996513487, speed: 1.779204891254465, phase: 3.6544289421926175),
    .init(x: 0.08889903406311606, y: 0.3931133694838731, speed: 0.34608880774162215, phase: 1.0500853048918501),
    .init(x: 0.4946786335725434, y: 0.3463927297287802, speed: 1.2162344529677338, phase: 6.22139656337246),
    .init(x: 0.3355102503002525, y: 0.6315444418144719, speed: 0.34825594969708595, phase: 0.08007605597878653),
    .init(x: 0.676321242620783, y: 0.7094003882074376, speed: 1.4736892921610567, phase: 0.4186636059247886),
    .init(x: 0.5747455608700148, y: 0.1076139131813516, speed: 1.5384700803193105, phase: 1.4818861908654648),
    .init(x: 0.8764037975136014, y: 0.6408519258202157, speed: 0.5785589249520056, phase: 5.662675885107691),
    .init(x: 0.9486684151378634, y: 0.9061610629261293, speed: 1.7363370753808256, phase: 0.04994785267299386),
    .init(x: 0.49328722808410763, y: 0.6218345844444529, speed: 1.610250821825444, phase: 5.7362577576522344),
    .init(x: 0.12182597723443633, y: 0.42902874126979207, speed: 0.5639782880236897, phase: 4.048746198396456),
    .init(x: 0.5198484934709849, y: 0.05996659516984315, speed: 0.2965311018552126, phase: 2.1280671672084415),
    .init(x: 0.26031223404087267, y: 0.6557709715766442, speed: 1.2590301428331474, phase: 5.879244759589636),
    .init(x: 0.05420663536118675, y: 0.6440827196834926, speed: 0.5201991194801616, phase: 2.2160427408368335),
    .init(x: 0.7900387253491189, y: 0.19279370421366882, speed: 1.8191873638158522, phase: 3.8062074045070293),
    .init(x: 0.7771918133390695, y: 0.10144054467043317, speed: 0.7529766492247252, phase: 3.50078704881825),
    .init(x: 0.5430746514028596, y: 0.7620878754361124, speed: 0.9029101041366151, phase: 5.74436252813768),
    .init(x: 0.17656382872871457, y: 0.15678595701934273, speed: 0.5443432462990716, phase: 1.9650089249718494),
    .init(x: 0.30779099708797764, y: 0.31113274252850986, speed: 1.6086952786138233, phase: 4.297022045244699),
    .init(x: 0.7219832176435517, y: 0.8368986022158706, speed: 1.2797305218319859, phase: 2.63759581711608),
    .init(x: 0.8226816347335919, y: 0.3247909308960121, speed: 0.5444577133702089, phase: 4.563221963826868),
    .init(x: 0.707910043245216, y: 0.6479351622549889, speed: 0.4382477376240108, phase: 6.121510828615985),
    .init(x: 0.03553359122045607, y: 0.32799445812934136, speed: 1.786360285871649, phase: 0.2681417547429819),
    .init(x: 0.4394193005570388, y: 0.37289064265982463, speed: 1.0815204045169242, phase: 2.0570094044559175),
    .init(x: 0.8601734845291703, y: 0.9557988604947297, speed: 0.8741071396852532, phase: 1.5728428063746662),
    .init(x: 0.47227897769376836, y: 0.14272160691356817, speed: 1.7843025314013925, phase: 1.6232824539757806),
    .init(x: 0.5647676476627689, y: 0.39849209517112505, speed: 0.6018655649456893, phase: 4.645311559231365),
    .init(x: 0.8733979243654699, y: 0.18506610897606968, speed: 0.5040727275751021, phase: 5.068128905628089),
    .init(x: 0.04113835573923641, y: 0.8005546517603845, speed: 1.6887882292586895, phase: 4.799644124834001),
    .init(x: 0.6866843208060376, y: 0.16933393133300534, speed: 0.27879156726784055, phase: 0.07305052207713388),
    .init(x: 0.6579141569629482, y: 0.9112177597615086, speed: 1.2567118925190492, phase: 2.5979865281197854),
    .init(x: 0.3824454526806592, y: 0.1536305854207045, speed: 0.34027510560362356, phase: 3.7925222865099224),
    .init(x: 0.23922076548815385, y: 0.8658641613759003, speed: 0.39344127540472074, phase: 3.7257708727775163),
    .init(x: 0.43332590153962736, y: 0.07440896597106594, speed: 1.2126445681350024, phase: 0.3563347877482832),
    .init(x: 0.9211269379803212, y: 0.6162850959117488, speed: 0.383855695291665, phase: 1.5685840530474797),
    .init(x: 0.8534084530385623, y: 0.3725750174583732, speed: 0.7985387366693666, phase: 3.025183299039266),
    .init(x: 0.20272117155907998, y: 0.29754692606352984, speed: 1.506838841943529, phase: 4.01123527196733),
    .init(x: 0.624914159097024, y: 0.4071414727686685, speed: 1.0060790296256494, phase: 0.16519149377332812),
    .init(x: 0.10176156690163707, y: 0.9025542870687026, speed: 1.0468113693696606, phase: 0.8136343870348728),
    .init(x: 0.690356271531597, y: 0.1376505536064787, speed: 1.6494512741544765, phase: 4.843859215672568),
    .init(x: 0.8945084264854717, y: 0.36633561180177054, speed: 0.5671530006601907, phase: 6.262559702633491),
    .init(x: 0.5171632606564336, y: 0.5236824249101268, speed: 1.270517719395652, phase: 0.607258077233145),
    .init(x: 0.020510784103514923, y: 0.9484699601513193, speed: 1.051705195294284, phase: 2.6457877179508533),
    .init(x: 0.5954094785048964, y: 0.03934959663909776, speed: 0.42688970589737496, phase: 1.5059873495104175),
    .init(x: 0.49841415290695446, y: 0.4317916826935655, speed: 0.4094291732566123, phase: 3.673943746051004),
    .init(x: 0.34242092291979875, y: 0.22794495490370348, speed: 1.411719228401809, phase: 2.9102459528917106),
    .init(x: 0.6967027985044265, y: 0.3381068438247108, speed: 1.376570149600024, phase: 1.2463957707826556),
    .init(x: 0.10232672508493623, y: 0.9350475453710745, speed: 0.7787659532529521, phase: 0.19078110292555295),
    .init(x: 0.5840525496434622, y: 0.7396594180603187, speed: 0.8108960112719423, phase: 5.393201835366984),
    .init(x: 0.8219224550836398, y: 0.2245657646700292, speed: 0.5532587539697496, phase: 1.6979165116475043),
    .init(x: 0.1783272337836761, y: 0.13967861916233826, speed: 1.8944209273188153, phase: 3.4310861762441878),
    .init(x: 0.8819624376686032, y: 0.23325556576875062, speed: 1.4033937509969538, phase: 5.916295617619747),
    .init(x: 0.051910693422408394, y: 0.24205420990238613, speed: 1.8961889831618663, phase: 3.9822889431264934),
    .init(x: 0.2873782609853919, y: 0.9565135842838458, speed: 1.4116703423931305, phase: 3.638511295462451),
    .init(x: 0.5152458990692628, y: 0.36881164393928667, speed: 0.5883770107614542, phase: 6.03832466039912),
    .init(x: 0.020588035856834108, y: 0.5299359156482555, speed: 1.7466266438533034, phase: 5.2292793334093455),
    .init(x: 0.07076464751115052, y: 0.5012247556153248, speed: 0.38220579242245034, phase: 5.965542308379373),
    .init(x: 0.3254421091281505, y: 0.36057526456037037, speed: 0.4280772341708351, phase: 5.596920571307397),
    .init(x: 0.28661231255484676, y: 0.44131226934076584, speed: 1.5514446385227918, phase: 0.9975444846290783),
    .init(x: 0.36088286257713975, y: 0.09114007740495833, speed: 1.3051244656943821, phase: 0.8661733700834937),
    .init(x: 0.6525724462735164, y: 0.09019595695253202, speed: 0.9097800221045373, phase: 2.550060792607922),
    .init(x: 0.24381209603532872, y: 0.7070725841280843, speed: 0.666212149231462, phase: 4.396964068294105),
    .init(x: 0.31829436185574567, y: 0.24488492009741802, speed: 0.48872848183491274, phase: 4.838868384635342),
    .init(x: 0.3329717396125812, y: 0.10448759093173055, speed: 0.895459855150218, phase: 6.064586893707107),
    .init(x: 0.7341145056077534, y: 0.31129763221005, speed: 0.6682049743647935, phase: 0.009184681826985355),
    .init(x: 0.09398451163481081, y: 0.2975596325250748, speed: 0.7819091244764182, phase: 5.857605604874237),
    .init(x: 0.732775911608896, y: 0.026614328225840644, speed: 1.6684541964359816, phase: 2.7389948269642783),
    .init(x: 0.42494617149533276, y: 0.09386895305321785, speed: 0.6294667244711094, phase: 3.307016602817705),
    .init(x: 0.6116957133686536, y: 0.9383717284913471, speed: 1.233921272256202, phase: 2.542776544922947),
    .init(x: 0.3325886609021692, y: 0.5869037952612245, speed: 0.9502576495969481, phase: 0.7043619539371322),
    .init(x: 0.41189704423449935, y: 0.6806118002148089, speed: 1.3621171175206488, phase: 1.637532638282173),
    .init(x: 0.450719078749788, y: 0.17665791007702214, speed: 1.8738974074151524, phase: 5.196543395187387),
    .init(x: 0.04952881059582137, y: 0.10996908930295723, speed: 0.5269081497171435, phase: 0.43579454249690325),
    .init(x: 0.46512347302223433, y: 0.2906597811293119, speed: 1.3193182891488378, phase: 0.607940816891815),
    .init(x: 0.0415555703612267, y: 0.18439333399635582, speed: 1.8849458151301732, phase: 2.4049714009749454),
    .init(x: 0.8214998016819377, y: 0.5386809177565617, speed: 1.2132175071857088, phase: 2.9351496599304117),
    .init(x: 0.6316560288214965, y: 0.7196489954475709, speed: 1.6170145537080196, phase: 1.647520998802892),
    .init(x: 0.5969191439294695, y: 0.3447891893481748, speed: 0.7193820374189953, phase: 3.1269783016679593),
    .init(x: 0.312286571587708, y: 0.7358859688464164, speed: 1.1918981228660481, phase: 3.37751784283114),
    .init(x: 0.5405842299133273, y: 0.13534352658719517, speed: 0.5190837324207987, phase: 4.225375184348614),
    .init(x: 0.5630424706931322, y: 0.04858950688207675, speed: 0.404403053631038, phase: 6.124263557342374),
    .init(x: 0.7728836975526241, y: 0.043797225375909465, speed: 1.833303483506244, phase: 1.5744225416553423),
    .init(x: 0.15498594996676873, y: 0.7554000900550918, speed: 1.5193299851032673, phase: 5.6788429470285475),
    .init(x: 0.12009672192030296, y: 0.9196163664099926, speed: 1.0290826417622896, phase: 3.370215941999052),
    .init(x: 0.34460236214868434, y: 0.018422839646623834, speed: 0.9214233442756863, phase: 3.3305980363090932),
    .init(x: 0.7141816626277485, y: 0.7365739061968299, speed: 0.2847815017333242, phase: 4.398117318328638),
    .init(x: 0.9740381949206492, y: 0.5237740355711209, speed: 1.4381204987098097, phase: 4.935509161976323),
    .init(x: 0.5861924249425651, y: 0.36599167869084737, speed: 1.5082526749126655, phase: 5.160118108872922),
    .init(x: 0.8590964519163145, y: 0.6157120539714281, speed: 1.8347371654485054, phase: 2.5877924125339655),
    .init(x: 0.2314902108580703, y: 0.5406748050205495, speed: 1.556374290749065, phase: 5.319042780784897),
    .init(x: 0.021149540320932303, y: 0.11613377009147097, speed: 0.5181739235693142, phase: 1.964166137802188),
    .init(x: 0.26080888016918646, y: 0.8546217491959464, speed: 0.27134160172393257, phase: 1.1563145345237729),
    .init(x: 0.07824452594711673, y: 0.3784241817726741, speed: 1.551044094381741, phase: 1.3274723677502378),
    .init(x: 0.8457903406666285, y: 0.5379634332870196, speed: 0.9117005938303879, phase: 5.132101855195737),
    .init(x: 0.7358794844152509, y: 0.6017141146319499, speed: 0.8130221694432388, phase: 0.4689290156355658),
    .init(x: 0.48275783831294716, y: 0.7443554874121091, speed: 0.4337794351520393, phase: 0.9859323695530666),
    .init(x: 0.36706556092572273, y: 0.15527814723963762, speed: 1.5586143571932198, phase: 5.733794633858419),
    .init(x: 0.2163857826781257, y: 0.8430205880955903, speed: 1.132689974447541, phase: 4.7330714495541155),
    .init(x: 0.7979069706642992, y: 0.22329491529275391, speed: 0.648920028200588, phase: 2.3593450898410233),
    .init(x: 0.9240680530644677, y: 0.2489245102386718, speed: 0.9675819487201871, phase: 3.1591082235008634),
    .init(x: 0.258585591978578, y: 0.7049327302114241, speed: 1.2255395550847568, phase: 2.5259390252558562),
    .init(x: 0.20489279189732745, y: 0.28510977416993544, speed: 1.288601559593426, phase: 3.9149711488733767),
    .init(x: 0.4614629259940629, y: 0.19308689134842005, speed: 0.41135330856335145, phase: 1.9552770370776866),
    .init(x: 0.48187723863404486, y: 0.003013954437713462, speed: 1.7254887056455592, phase: 5.929916302460547),
    .init(x: 0.20750322632736817, y: 0.7474773275563261, speed: 0.674836102524011, phase: 1.7439023599867176),
    .init(x: 0.2974791016929702, y: 0.009753854701136766, speed: 1.70220548635363, phase: 1.6158684302416813),
    .init(x: 0.3339728863105621, y: 0.5164467477472984, speed: 1.684445970442949, phase: 2.3215674182161754),
    .init(x: 0.5924281400762291, y: 0.4458550954908147, speed: 0.39841228784811755, phase: 6.234966898398816),
    .init(x: 0.29392776724794323, y: 0.8289246316478759, speed: 1.6578965218722355, phase: 3.309753735437102),
    .init(x: 0.5779764820589067, y: 0.49667858144628263, speed: 1.3592859439649434, phase: 2.6370919741739534),
    .init(x: 0.8289613655219469, y: 0.0656042415322513, speed: 1.0419283210749757, phase: 0.8746097243337898),
    .init(x: 0.0031260507393675585, y: 0.3735480069141549, speed: 0.7366748171533168, phase: 1.2441540125927393),
    .init(x: 0.17904179545843846, y: 0.7369387712050463, speed: 1.5253073943104718, phase: 4.359595875887814),
    .init(x: 0.5740478465986832, y: 0.6563599432339945, speed: 0.3591002538937983, phase: 5.344399060019139),
    .init(x: 0.7610408608905022, y: 0.26279218727551734, speed: 1.5468605671149644, phase: 0.3093242877497528),
    .init(x: 0.6267929150537107, y: 0.0333964030764472, speed: 0.49411937560477925, phase: 1.774304837954609),
    .init(x: 0.9168807706955469, y: 0.7431189485716223, speed: 1.2299308746229745, phase: 3.4912486886606704),
    .init(x: 0.11755722156219317, y: 0.8136723317937826, speed: 1.0781338718836402, phase: 5.961767580359654),
    .init(x: 0.03593840254626646, y: 0.15761050426223355, speed: 1.780567640873091, phase: 6.219513144232722),
    .init(x: 0.9565416456716558, y: 0.41969302561766875, speed: 0.637798752245093, phase: 2.204327065962858),
    .init(x: 0.3929517217070848, y: 0.4085434274334223, speed: 1.1016634959798564, phase: 2.356584785603774),
    .init(x: 0.7028080267588167, y: 0.3558320891326604, speed: 1.201072819009538, phase: 0.8475301460436105),
    .init(x: 0.38406840944911114, y: 0.4852627273459946, speed: 1.356001220163227, phase: 2.504026309738173),
    .init(x: 0.24117071167871895, y: 0.8666259833183205, speed: 0.8254788160311035, phase: 4.050685454949658),
    .init(x: 0.022210699927336708, y: 0.14029875743516373, speed: 1.4237719209381756, phase: 3.354174679273813),
    .init(x: 0.6704285121997716, y: 0.9734749507649311, speed: 1.8053453603927931, phase: 6.268029610882488),
    .init(x: 0.13165040975924613, y: 0.3103378342426655, speed: 0.9692563305247573, phase: 3.1114310971154024),
    .init(x: 0.8714577353887973, y: 0.49020219709384527, speed: 0.3750917743603077, phase: 4.207715401980744),
    .init(x: 0.5191240472751051, y: 0.9605173426341667, speed: 0.5258659496854136, phase: 0.5576577440759389),
    .init(x: 0.9204174655766152, y: 0.01238427138556708, speed: 1.000939544431984, phase: 1.1740133397810744),
    .init(x: 0.6631148044845084, y: 0.05041396561475264, speed: 0.7255167370543266, phase: 2.134582737562162),
    .init(x: 0.845670847552677, y: 0.4158737399753406, speed: 1.3754979064940074, phase: 0.10318665054732648),
    .init(x: 0.020302966129008393, y: 0.7038383954600359, speed: 1.6704975747479227, phase: 2.0936706666223257),
    .init(x: 0.9415746681905843, y: 0.8444174984242212, speed: 0.9358370095859484, phase: 0.7860796722113185),
    .init(x: 0.835126437736693, y: 0.5736786124636077, speed: 1.6339976058504564, phase: 0.8610393981158669),
    .init(x: 0.3707016851397358, y: 0.8923258107555444, speed: 1.4897296729674911, phase: 1.9357650594095885),
    .init(x: 0.6322535004802173, y: 0.4264553573950226, speed: 1.3877654258179315, phase: 3.8885602910878285),
    .init(x: 0.5599300921936153, y: 0.0021939179558275734, speed: 1.4036401385039252, phase: 5.1970482991517),
    .init(x: 0.5119005730575278, y: 0.581663890725855, speed: 0.2884422391879703, phase: 4.346054246091316),
    .init(x: 0.8709089796499178, y: 0.2872177090469179, speed: 1.7046062034723213, phase: 6.07156693832103),
    .init(x: 0.5960911384910198, y: 0.3298716641607804, speed: 1.7074869187962753, phase: 2.349355797383574),
    .init(x: 0.771106641736077, y: 0.8338298118452944, speed: 1.5719234031833007, phase: 4.98109916462738),
    .init(x: 0.5322542402607399, y: 0.1398064372716583, speed: 0.32203153688693453, phase: 5.280646921873202),
    .init(x: 0.5084127945594248, y: 0.9706274871416067, speed: 1.2379234109536406, phase: 1.5191073376678899),
    .init(x: 0.5596031783618385, y: 0.41372701955149804, speed: 1.8567247926031636, phase: 3.4149091808328493),
    .init(x: 0.9674406413796542, y: 0.2174816302596333, speed: 0.7451202164156139, phase: 1.2739116201170915),
    .init(x: 0.9333860506497451, y: 0.9387507435442151, speed: 1.6548489244935167, phase: 2.226730814589081),
    .init(x: 0.8140028965572377, y: 0.8306620810540476, speed: 1.240379924859453, phase: 3.385301574968137),
    .init(x: 0.391174103642261, y: 0.9611690746544892, speed: 1.1301473096075625, phase: 4.926206232976809),
    .init(x: 0.7065264360532363, y: 0.6918239598157586, speed: 0.8867145602039738, phase: 3.242733896399357),
    .init(x: 0.06210237814498931, y: 0.05727054570189971, speed: 1.3210503386793795, phase: 4.786181071741681),
    .init(x: 0.5200488380933407, y: 0.9750755097395196, speed: 1.1228796452032281, phase: 0.7348633159889496),
    .init(x: 0.07324642458011021, y: 0.49282391595906483, speed: 1.5951284849594392, phase: 0.1888783275499891),
    .init(x: 0.30430715240420303, y: 0.9171721363433863, speed: 1.331544643488614, phase: 3.9614008627105908),
    .init(x: 0.865758824441451, y: 0.24744670281716186, speed: 1.1996277001021167, phase: 1.5324007618663718),
    .init(x: 0.31724512842598684, y: 0.7886255391225455, speed: 0.3494375734640306, phase: 3.553700913201544),
    .init(x: 0.34021511979619834, y: 0.8027876746822667, speed: 1.084711961796383, phase: 2.839710908523959),
    .init(x: 0.26514683957606755, y: 0.9517674514793807, speed: 0.2671484866310992, phase: 5.276148848895049),
    .init(x: 0.7469289590094633, y: 0.930661563978906, speed: 1.1860725586457832, phase: 3.349009270095363),
    .init(x: 0.4060485835988752, y: 0.322639964541662, speed: 1.1161271176069418, phase: 5.641586883674071),
    .init(x: 0.14990368067088866, y: 0.10859065206224505, speed: 1.65978477042847, phase: 6.215959506210241),
    .init(x: 0.7422178305519301, y: 0.3284263597690006, speed: 0.4866247577640629, phase: 4.074109104382782),
    .init(x: 0.5035177092909234, y: 0.6853780230362712, speed: 0.3236876996937225, phase: 4.583786863740695),
    .init(x: 0.18509596415349228, y: 0.04353997437032309, speed: 1.4490556103483112, phase: 4.339236652228664),
    .init(x: 0.539608561948468, y: 0.4453293772550966, speed: 1.582459398788847, phase: 2.7343234448889726),
    .init(x: 0.20960019654775608, y: 0.635378016855023, speed: 1.2249415630802214, phase: 3.8537258696989807),
    .init(x: 0.023516241210432387, y: 0.4697558004275282, speed: 0.2737227323348931, phase: 0.08068759072409566),
    .init(x: 0.38978240956458843, y: 0.3843240588985807, speed: 1.4635156816421113, phase: 2.494028049760684),
    .init(x: 0.39905347409122083, y: 0.3720533057871326, speed: 1.4357920065015937, phase: 1.4356452780096853),
    .init(x: 0.9077285203362174, y: 0.9000304374630256, speed: 1.1714317908742897, phase: 4.622945884766567),
    .init(x: 0.9647250750888726, y: 0.1942396238534706, speed: 1.5006999985156604, phase: 4.287317184045447),
    .init(x: 0.11681289037625031, y: 0.7784235831337327, speed: 0.5436323274995145, phase: 3.679024729782658),
    .init(x: 0.9268034465744532, y: 0.763147026544127, speed: 1.4846081565530407, phase: 0.03727194739841319),
    .init(x: 0.198300155491421, y: 0.6926023951059419, speed: 0.3694092081452377, phase: 2.8480563072721488),
    .init(x: 0.7814394370183957, y: 0.19058136878116838, speed: 1.4963571705442344, phase: 6.116233129743703),
    .init(x: 0.7335048986301839, y: 0.9014901870411263, speed: 1.3154197389545215, phase: 4.811983084991392),
    .init(x: 0.512138877068041, y: 0.7751995515345738, speed: 0.5067139212164096, phase: 1.2788068635299832),
    .init(x: 0.9057873334401668, y: 0.6255729202377908, speed: 1.298219983133236, phase: 3.54742209497302),
    .init(x: 0.29327006012360257, y: 0.27860683871574987, speed: 1.2770369472971999, phase: 3.790361579098625)
  ]
var _bass: Double { neonClamp((((frame.subBass * 0.65) + frame.bass)), 0.0, 1.0) }

var _mids: Double { neonClamp(((((frame.lowMid * 0.35) + (frame.mid * 0.8)) + (frame.highMid * 0.3))), 0.0, 1.0) }

var _highs: Double { neonClamp(((((frame.highMid * 0.45) + (frame.treble * 0.7)) + (frame.air * 0.25))), 0.0, 1.0) }

var _energy: Double { neonClamp(frame.energy, 0.0, 1.0) }

var _centroid: Double { neonClamp(frame.brightness, 0.0, 1.0) }

var _beat: Double { neonClamp(max(frame.accentStrength, frame.flashStrength), 0.0, 1.0) }

func paint(_ canvas: Canvas, _ size: Size) -> Void {
let t = neonModulo(((time * motion)), 1.0)
let intensity = neonClamp(manualIntensity, 0.1, 2.0)
let signal = max(_energy, max(_bass, max(_mids, _highs)))
let idleBase = ((signal < 0.025) ? 0.26 : 0.08)
let bassPulse = (neonClamp(((((idleBase * 0.58) + (_bass * 0.95)) + (_energy * 0.25))), 0.0, 1.0) * intensity)
let midPulse = (neonClamp(((((idleBase * 0.88) + (_mids * 0.85)) + (_energy * 0.18))), 0.0, 1.0) * intensity)
let highPulse = (neonClamp(((((idleBase * 0.62) + (_highs * 0.9)) + (_centroid * 0.22))), 0.0, 1.0) * intensity)
let beatPulse = (_beat * intensity)
let idleGlow = (0.16 + (sin(((t * Double.pi) * 2.0)) * 0.035))
let vanishingPoint = Offset((size.width * ((0.5 + (sin(((t * Double.pi) * 2.0)) * 0.014)))), (size.height * (((0.43 - (bassPulse * 0.018)) + (cos(((t * Double.pi) * 2.0)) * 0.008)))))
_drawRoom(canvas, size, vanishingPoint, t, idleGlow, bassPulse, midPulse)
_drawAtmosphericVeils(canvas, size, vanishingPoint, t, bassPulse, midPulse)
_drawCurvedBackdrop(canvas, size, vanishingPoint, t, idleGlow, bassPulse, midPulse, highPulse)
_drawVolumetricBeams(canvas, size, vanishingPoint, t, idleGlow, bassPulse, midPulse)
_drawLedWalls(canvas, size, vanishingPoint, t, bassPulse, midPulse)
_drawLedMatrixCurtains(canvas, size, vanishingPoint, t, bassPulse, midPulse, highPulse)
_drawPrismaticArchitecture(canvas, size, vanishingPoint, t, bassPulse, midPulse, highPulse)
_drawCeilingRig(canvas, size, vanishingPoint, t, bassPulse, highPulse)
_drawTopLightCones(canvas, size, vanishingPoint, t, bassPulse, highPulse)
_drawNeonTubeFrame(canvas, size, vanishingPoint, t, bassPulse, midPulse, highPulse)
_drawReflectiveFloor(canvas, size, vanishingPoint, t, bassPulse, midPulse)
_drawFloorGloss(canvas, size, vanishingPoint, t, bassPulse, midPulse)
_drawStageCore(canvas, size, vanishingPoint, t, idleGlow, bassPulse, beatPulse)
_drawSpeakerStacks(canvas, size, vanishingPoint, t, bassPulse, midPulse)
_drawArchitecturalRings(canvas, size, vanishingPoint, t, bassPulse, midPulse)
if spectrumEnabled {
_drawEmbeddedSpectrum(canvas, size, vanishingPoint, bassPulse, midPulse, highPulse)
}
if lasersEnabled {
_drawLaserRibbons(canvas, size, vanishingPoint, t, beatPulse, highPulse)
}
if particlesEnabled {
_drawAtmosphericDust(canvas, size, t, highPulse, midPulse)
}
_drawLensBloom(canvas, size, vanishingPoint, t, bassPulse, midPulse, highPulse)
_drawForegroundEnergy(canvas, size, t, bassPulse, midPulse, highPulse)
_drawBeatFlash(canvas, size, beatPulse, bassPulse)
_drawVignette(canvas, size)
}

func _drawRoom(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ idleGlow: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let bgRect = (Offset.zero & size)
canvas.drawRect(bgRect, neonApply(Paint()) { value0 in value0.color = Color(0xFF020207) })
canvas.drawRect(bgRect, neonApply(Paint()) { value1 in value1.shader = RadialGradient(center: Alignment(((((vp.dx / size.width) - 0.5)) * 1.2), ((((vp.dy / size.height) - 0.5)) * 1.2)), radius: 0.9, colors: [Color.lerp(palette[Int(1.0)], Colors.white, 0.08).withValues(alpha: ((0.28 + (idleGlow * 0.14)) + (bassPulse * 0.13))), palette[Int(0.0)].withValues(alpha: (0.12 + (midPulse * 0.08))), Color(0xFF05040A), Colors.black], stops: [0.0, 0.28, 0.68, 1.0]).createShader(bgRect) })
let rearWall = RRect.fromRectAndRadius(Rect.fromCenter(center: vp.translate(0.0, (size.height * 0.012)), width: (size.width * 0.76), height: (size.height * 0.33)), Radius.circular(24.0))
canvas.drawRRect(rearWall, neonApply(Paint()) { value2 in value2.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.045), palette[Int(1.0)].withValues(alpha: (0.070 + (bassPulse * 0.045))), Colors.black.withValues(alpha: 0.16)]).createShader(rearWall.outerRect) })
let wallStroke = neonApply(Paint()) { value3 in value3.style = PaintingStyle.stroke; value3.strokeWidth = 1.1; value3.color = Colors.white.withValues(alpha: (0.10 + (midPulse * 0.07))) }
canvas.drawRRect(rearWall, wallStroke)
do {
var i = 0.0
while (i < 8.0) {
let y = (rearWall.outerRect.top + (rearWall.outerRect.height * ((0.14 + (i * 0.1)))))
let alpha = ((0.030 + (((sin((((t * Double.pi) * 2.0) + i)) + 1.0)) * 0.014)) + (midPulse * 0.026))
canvas.drawLine(Offset((rearWall.outerRect.left + 14.0), y), Offset((rearWall.outerRect.right - 14.0), y), neonApply(Paint()) { value4 in value4.strokeWidth = 1.0; value4.color = Colors.white.withValues(alpha: alpha) })
i += 1.0
}
}
}

func _drawVolumetricBeams(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ idleGlow: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let beamPaint = neonApply(Paint()) { value5 in value5.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 5.0) {
let side = ((Int(i) % 2 == 0) ? -(1.0) : 1.0)
let source = Offset((size.width * (((side < 0.0) ? (0.08 + (i * 0.028)) : (0.92 - (i * 0.026))))), (size.height * ((0.08 + (i * 0.035)))))
let sway = ((sin((((t * Double.pi) * 2.0) + (i * 0.83))) * size.width) * ((0.045 + (midPulse * 0.025))))
let target = vp.translate(sway, (size.height * (((0.18 + (i * 0.025)) + (bassPulse * 0.035)))))
let spread = (size.width * (((0.15 + (i * 0.018)) + (bassPulse * 0.035))))
let path = neonApply(Path()) { value6 in value6.moveTo((source.dx - ((side * size.width) * 0.018)), source.dy); value6.lineTo((target.dx - (spread * side)), (target.dy + (size.height * 0.24))); value6.quadraticBezierTo(target.dx, (target.dy + (size.height * 0.34)), (target.dx + (spread * side)), (target.dy + (size.height * 0.24))); value6.lineTo((source.dx + ((side * size.width) * 0.018)), source.dy); value6.close() }
let color = palette[Int(neonModulo(i, Double(palette.count)))]
_ = neonApply(beamPaint) { value7 in value7.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: ((0.20 + (idleGlow * 0.08)) + (midPulse * 0.10))), color.withValues(alpha: (0.070 + (bassPulse * 0.065))), Colors.transparent]).createShader(path.getBounds()); value7.maskFilter = MaskFilter.blur(BlurStyle.normal, (22.0 + (bassPulse * 16.0))) }
canvas.drawPath(path, beamPaint)
i += 1.0
}
}
let hazeCenter = vp.translate(0.0, (size.height * 0.16))
canvas.drawCircle(hazeCenter, (size.longestSide * ((0.26 + (bassPulse * 0.08)))), neonApply(Paint()) { value8 in value8.shader = RadialGradient(colors: [Colors.white.withValues(alpha: (0.15 + (bassPulse * 0.075))), palette[Int(1.0)].withValues(alpha: (0.13 + (midPulse * 0.075))), Colors.transparent]).createShader(Rect.fromCircle(center: hazeCenter, radius: (size.longestSide * ((0.32 + (bassPulse * 0.08)))))); value8.blendMode = BlendMode.plus })
}

func _drawAtmosphericVeils(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let paint = neonApply(Paint()) { value9 in value9.style = PaintingStyle.stroke; value9.strokeCap = StrokeCap.round; value9.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 7.0) {
let y = (size.height * ((0.30 + (i * 0.075))))
let phase = (((t * Double.pi) * ((0.75 + (i * 0.07)))) + (i * 0.82))
let path = neonApply(Path()) { value10 in value10.moveTo((-(size.width) * 0.12), (y + ((sin(phase) * size.height) * 0.020))); value10.cubicTo((size.width * 0.18), (y - (size.height * ((0.06 + (sin((phase * 0.7)) * 0.018))))), (size.width * 0.42), (y + (size.height * ((0.04 + (cos(phase) * 0.020))))), vp.dx, (y + ((sin((phase * 1.2)) * size.height) * 0.035))); value10.cubicTo((size.width * 0.62), (y - (size.height * ((0.045 + (cos((phase * 0.9)) * 0.018))))), (size.width * 0.86), (y + (size.height * ((0.052 + (sin(phase) * 0.018))))), (size.width * 1.12), (y + ((cos((phase * 1.1)) * size.height) * 0.020))) }
let color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.18)
_ = neonApply(paint) { value11 in value11.color = color.withValues(alpha: ((0.030 + (midPulse * 0.055)) + (i * 0.004))); value11.strokeWidth = (size.height * ((0.020 + (bassPulse * 0.012)))); value11.maskFilter = MaskFilter.blur(BlurStyle.normal, (28.0 + (bassPulse * 18.0))) }
canvas.drawPath(path, paint)
i += 1.0
}
}
}

func _drawCurvedBackdrop(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ idleGlow: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let topWidth = (size.width * ((0.58 + (bassPulse * 0.018))))
let bottomWidth = (size.width * ((0.72 + (bassPulse * 0.035))))
let topY = (size.height * 0.265)
let bottomY = (size.height * 0.675)
let leftTop = Offset((vp.dx - (topWidth / 2.0)), topY)
let rightTop = Offset((vp.dx + (topWidth / 2.0)), topY)
let leftBottom = Offset((vp.dx - (bottomWidth / 2.0)), bottomY)
let rightBottom = Offset((vp.dx + (bottomWidth / 2.0)), bottomY)
let screen = neonApply(Path()) { value12 in value12.moveTo(leftTop.dx, leftTop.dy); value12.cubicTo((vp.dx - (topWidth * 0.34)), (topY - (size.height * 0.018)), (vp.dx + (topWidth * 0.34)), (topY - (size.height * 0.018)), rightTop.dx, rightTop.dy); value12.lineTo(rightBottom.dx, rightBottom.dy); value12.cubicTo((vp.dx + (bottomWidth * 0.22)), (bottomY + (size.height * 0.035)), (vp.dx - (bottomWidth * 0.22)), (bottomY + (size.height * 0.035)), leftBottom.dx, leftBottom.dy); value12.close() }
let bounds = screen.getBounds()
canvas.drawPath(screen, neonApply(Paint()) { value13 in value13.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [palette[Int(0.0)].withValues(alpha: (0.12 + (bassPulse * 0.05))), Color(0xFF06101A).withValues(alpha: 0.70), palette[Int(1.0)].withValues(alpha: (0.14 + (midPulse * 0.06))), Color(0xFF030208)], stops: [0.0, 0.32, 0.70, 1.0]).createShader(bounds) })
let glowPaint = neonApply(Paint()) { value14 in value14.style = PaintingStyle.stroke; value14.strokeWidth = (2.0 + (bassPulse * 2.0)); value14.color = Color.lerp(palette[Int(1.0)], Colors.white, 0.15).withValues(alpha: ((0.16 + (idleGlow * 0.10)) + (bassPulse * 0.10))); value14.maskFilter = MaskFilter.blur(BlurStyle.normal, (12.0 + (bassPulse * 8.0))); value14.blendMode = BlendMode.plus }
canvas.drawPath(screen, glowPaint)
canvas.drawPath(screen, neonApply(Paint()) { value15 in value15.style = PaintingStyle.stroke; value15.strokeWidth = 0.8; value15.color = Colors.white.withValues(alpha: (0.13 + (midPulse * 0.05))); value15.blendMode = BlendMode.plus })
canvas.save()
canvas.clipPath(screen)
_drawBackdropWave(canvas, size, bounds, t, bassPulse, midPulse, highPulse)
_drawBackdropPixelTexture(canvas, bounds, t, bassPulse, midPulse)
canvas.restore()
}

func _drawBackdropWave(_ canvas: Canvas, _ size: Size, _ bounds: Rect, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let paint = neonApply(Paint()) { value16 in value16.style = PaintingStyle.stroke; value16.strokeCap = StrokeCap.round; value16.strokeJoin = StrokeJoin.round; value16.blendMode = BlendMode.plus }
do {
var layer = 0.0
while (layer < 4.0) {
let path = Path()
let baseY = (bounds.center.dy + (bounds.height * ((-(0.18) + (layer * 0.11)))))
let amp = (bounds.height * (((0.035 + (layer * 0.012)) + (midPulse * 0.040))))
let phase = (((t * Double.pi) * ((1.8 + (layer * 0.28)))) + (layer * 1.3))
do {
var i = 0.0
while (i <= 72.0) {
let p = (i / 72.0)
let x = (bounds.left + (bounds.width * p))
let envelope = neonClamp(sin((p * Double.pi)), 0.0, 1.0)
let y = ((baseY + ((sin((((p * Double.pi) * ((2.2 + (layer * 0.7)))) + phase)) * amp) * envelope)) + (((cos((((p * Double.pi) * 7.0) - (phase * 0.72))) * amp) * 0.28) * envelope))
if (i == 0.0) {
path.moveTo(x, y)
} else {
path.lineTo(x, y)
}
i += 1.0
}
}
let color = Color.lerp(palette[Int(neonModulo(layer, Double(palette.count)))], Colors.white, 0.08)
_ = neonApply(paint) { value17 in value17.color = color.withValues(alpha: ((0.22 + (highPulse * 0.10)) + (layer * 0.025))); value17.strokeWidth = ((1.1 + (layer * 0.45)) + (bassPulse * 1.5)); value17.maskFilter = MaskFilter.blur(BlurStyle.normal, (8.0 + (layer * 4.0))) }
canvas.drawPath(path, paint)
_ = neonApply(paint) { value18 in value18.color = color.withValues(alpha: (0.38 + (highPulse * 0.12))); value18.strokeWidth = (0.65 + (layer * 0.18)); value18.maskFilter = nil }
canvas.drawPath(path, paint)
layer += 1.0
}
}
let pulseCenter = Offset(bounds.center.dx, (bounds.center.dy + (bounds.height * 0.04)))
canvas.drawCircle(pulseCenter, (size.shortestSide * ((0.20 + (bassPulse * 0.06)))), neonApply(Paint()) { value19 in value19.shader = RadialGradient(colors: [palette[Int(1.0)].withValues(alpha: (0.16 + (bassPulse * 0.12))), palette[Int(0.0)].withValues(alpha: (0.05 + (midPulse * 0.08))), Colors.transparent]).createShader(Rect.fromCircle(center: pulseCenter, radius: (size.shortestSide * ((0.24 + (bassPulse * 0.06)))))); value19.blendMode = BlendMode.plus })
}

func _drawBackdropPixelTexture(_ canvas: Canvas, _ bounds: Rect, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let paint = neonApply(Paint()) { value20 in value20.blendMode = BlendMode.plus }
do {
var col = 0.0
while (col < 18.0) {
let x = (bounds.left + ((bounds.width * ((col + 0.5))) / 18.0))
do {
var row = 0.0
while (row < 10.0) {
let y = (bounds.top + ((bounds.height * ((row + 0.5))) / 10.0))
let shimmer = (((sin(((((t * Double.pi) * 2.0) + (col * 0.55)) + (row * 0.88))) + 1.0)) * 0.5)
let alpha = neonClamp((((0.015 + (shimmer * 0.028)) + (midPulse * 0.030))), 0.0, 0.11)
let color = Color.lerp(palette[Int(neonModulo(((col + row)), Double(palette.count)))], Colors.white, 0.10)
paint.color = color.withValues(alpha: alpha)
let w = (bounds.width * ((0.012 + (bassPulse * 0.002))))
let h = (bounds.height * 0.010)
canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: w, height: h), Radius.circular(3.0)), paint)
row += 1.0
}
}
col += 1.0
}
}
}

func _drawLedWalls(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
for side in [-(1.0), 1.0] {
let outerTop = Offset(((side < 0.0) ? (-(size.width) * 0.05) : (size.width * 1.05)), (size.height * 0.16))
let outerBottom = Offset(((side < 0.0) ? (-(size.width) * 0.06) : (size.width * 1.06)), (size.height * 0.88))
let innerTop = Offset((vp.dx + ((side * size.width) * 0.17)), (size.height * 0.23))
let innerBottom = Offset((vp.dx + ((side * size.width) * 0.34)), (size.height * 0.90))
let wall = _quadPath(outerTop, innerTop, innerBottom, outerBottom)
let wallBounds = wall.getBounds()
canvas.drawPath(wall, neonApply(Paint()) { value21 in value21.shader = LinearGradient(begin: ((side < 0.0) ? Alignment.centerLeft : Alignment.centerRight), end: ((side < 0.0) ? Alignment.centerRight : Alignment.centerLeft), colors: [palette[Int(((side < 0.0) ? 1.0 : 0.0))].withValues(alpha: (0.055 + (midPulse * 0.025))), Colors.white.withValues(alpha: 0.026), Colors.black.withValues(alpha: 0.16)]).createShader(wallBounds) })
do {
var row = 0.0
while (row < 10.0) {
let r0 = (row / 10.0)
let r1 = (((row + 0.64)) / 10.0)
let outerA = _lerpOffset(outerTop, outerBottom, r0)
let innerA = _lerpOffset(innerTop, innerBottom, r0)
let outerB = _lerpOffset(outerTop, outerBottom, r1)
let innerB = _lerpOffset(innerTop, innerBottom, r1)
let columns = (3.0 + floor(((row / 2.0))))
do {
var col = 0.0
while (col < columns) {
let c0 = ((col / columns) + 0.03)
let c1 = (((col + 0.72)) / columns)
let a = _lerpOffset(outerA, innerA, c0)
let b = _lerpOffset(outerA, innerA, c1)
let c = _lerpOffset(outerB, innerB, c1)
let d = _lerpOffset(outerB, innerB, c0)
let shimmer = (((sin(((((t * Double.pi) * 2.0) + (row * 0.7)) + (col * 1.1))) + 1.0)) * 0.5)
let value = neonClamp(((((0.10 + (shimmer * 0.045)) + (midPulse * 0.085)) + (bassPulse * 0.030))), 0.0, 0.20)
let color = Color.lerp(palette[Int(neonModulo(((row + col)), Double(palette.count)))], Colors.white, 0.08)
let tilePath = _quadPath(a, b, c, d)
canvas.drawPath(tilePath, neonApply(Paint()) { value22 in value22.color = color.withValues(alpha: (value * 0.30)); value22.maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0); value22.blendMode = BlendMode.plus })
canvas.drawPath(tilePath, neonApply(Paint()) { value23 in value23.color = color.withValues(alpha: (value * 0.38)); value23.blendMode = BlendMode.plus })
col += 1.0
}
}
row += 1.0
}
}
}
}

func _drawLedMatrixCurtains(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let glowPaint = neonApply(Paint()) { value24 in value24.blendMode = BlendMode.plus }
let dotPaint = neonApply(Paint()) { value25 in value25.blendMode = BlendMode.plus }
for side in [-(1.0), 1.0] {
let outerTop = Offset(((side < 0.0) ? (-(size.width) * 0.02) : (size.width * 1.02)), (size.height * 0.17))
let outerBottom = Offset(((side < 0.0) ? (-(size.width) * 0.03) : (size.width * 1.03)), (size.height * 0.92))
let innerTop = Offset((vp.dx + ((side * size.width) * 0.22)), (size.height * 0.25))
let innerBottom = Offset((vp.dx + ((side * size.width) * 0.41)), (size.height * 0.91))
do {
var row = 0.0
while (row < 18.0) {
let r = (row / 17.0)
let left = _lerpOffset(outerTop, outerBottom, r)
let right = _lerpOffset(innerTop, innerBottom, r)
let columns = (5.0 + ((r * 7.0)).rounded(.toNearestOrAwayFromZero))
do {
var col = 0.0
while (col < columns) {
let c = (((col + 0.5)) / columns)
let position = _lerpOffset(left, right, c)
let depth = neonClamp((((r * 0.65) + (c * 0.35))), 0.0, 1.0)
let twinkle = (((sin((((((t * Double.pi) * 4.0) + (row * 0.72)) + (col * 1.19)) + side)) + 1.0)) * 0.5)
let musical = neonClamp(((((midPulse * 0.50) + (highPulse * 0.35)) + (bassPulse * 0.15))), 0.0, 1.0)
let alpha = neonClamp((((0.025 + (twinkle * 0.07)) + (musical * 0.13))), 0.0, 0.26)
let radius = (size.shortestSide * (((0.0045 + (depth * 0.006)) + (bassPulse * 0.002))))
let color = Color.lerp(palette[Int(neonModulo((((row + col) + (((side > 0.0) ? 1.0 : 0.0)))), Double(palette.count)))], Colors.white, 0.16)
_ = neonApply(glowPaint) { value26 in value26.color = color.withValues(alpha: (alpha * 0.55)); value26.maskFilter = MaskFilter.blur(BlurStyle.normal, (7.0 + (depth * 6.0))) }
canvas.drawCircle(position, (radius * 2.4), glowPaint)
_ = neonApply(dotPaint) { value27 in value27.color = color.withValues(alpha: (alpha + 0.04)); value27.maskFilter = nil }
canvas.drawCircle(position, radius, dotPaint)
col += 1.0
}
}
row += 1.0
}
}
}
}

func _drawPrismaticArchitecture(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let center = vp.translate(0.0, (size.height * 0.23))
let glowStroke = neonApply(Paint()) { value28 in value28.style = PaintingStyle.stroke; value28.strokeCap = StrokeCap.round; value28.strokeJoin = StrokeJoin.round; value28.blendMode = BlendMode.plus }
let crispStroke = neonApply(Paint()) { value29 in value29.style = PaintingStyle.stroke; value29.strokeCap = StrokeCap.round; value29.strokeJoin = StrokeJoin.round; value29.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 6.0) {
let rect = Rect.fromCenter(center: center.translate(0.0, (size.height * ((0.006 + (i * 0.010))))), width: (size.width * (((0.38 + (i * 0.105)) + (bassPulse * 0.035)))), height: (size.height * (((0.105 + (i * 0.050)) + (bassPulse * 0.012)))))
let phase = (((t * Double.pi) * 2.0) + (i * 0.58))
let start = (-(Double.pi) * ((0.96 + (sin(phase) * 0.026))))
let sweep = (Double.pi * (((0.92 + (midPulse * 0.10)) + (i * 0.006))))
let color = Color.lerp(palette[Int(neonModulo(((i + 1.0)), Double(palette.count)))], Colors.white, 0.10)
_ = neonApply(glowStroke) { value30 in value30.color = color.withValues(alpha: (((0.055 + (midPulse * 0.052)) + (highPulse * 0.022)) - (i * 0.004))); value30.strokeWidth = ((5.0 + (bassPulse * 5.0)) + (i * 0.55)); value30.maskFilter = MaskFilter.blur(BlurStyle.normal, (15.0 + (i * 3.0))) }
canvas.drawArc(rect, start, sweep, false, glowStroke)
_ = neonApply(crispStroke) { value31 in value31.color = Colors.white.withValues(alpha: ((0.030 + (highPulse * 0.048)) + (bassPulse * 0.020))); value31.strokeWidth = (0.55 + (bassPulse * 0.45)); value31.maskFilter = nil }
canvas.drawArc(rect, start, sweep, false, crispStroke)
i += 1.0
}
}
for side in [-(1.0), 1.0] {
let outerTop = Offset(((side < 0.0) ? (-(size.width) * 0.05) : (size.width * 1.05)), (size.height * 0.17))
let outerBottom = Offset(((side < 0.0) ? (-(size.width) * 0.03) : (size.width * 1.03)), (size.height * 0.94))
let innerTop = Offset((vp.dx + ((side * size.width) * 0.20)), (size.height * 0.25))
let innerBottom = Offset((vp.dx + ((side * size.width) * 0.43)), (size.height * 0.90))
do {
var i = 0.0
while (i < 7.0) {
let p = (((i + 0.5)) / 7.0)
let top = _lerpOffset(outerTop, innerTop, p)
let bottom = _lerpOffset(outerBottom, innerBottom, p)
let pull = ((side * size.width) * ((0.035 + (i * 0.004))))
let phase = ((((t * Double.pi) * 2.0) + (i * 0.77)) + side)
let path = neonApply(Path()) { value32 in value32.moveTo(top.dx, top.dy); value32.cubicTo(((top.dx - pull) + ((sin(phase) * size.width) * 0.012)), (size.height * 0.38), (bottom.dx + (pull * 0.45)), ((size.height * 0.64) + ((cos(phase) * size.height) * 0.010)), bottom.dx, bottom.dy) }
let color = Color.lerp(palette[Int(neonModulo(((i + (((side > 0.0) ? 2.0 : 0.0)))), Double(palette.count)))], Colors.white, 0.12)
let musical = neonClamp(((((midPulse * 0.55) + (highPulse * 0.32)) + (bassPulse * 0.18))), 0.0, 1.0)
let shimmer = (((sin((phase * 1.7)) + 1.0)) * 0.5)
_ = neonApply(glowStroke) { value33 in value33.color = color.withValues(alpha: (0.040 + (musical * 0.080))); value33.strokeWidth = (size.width * (((0.014 + (p * 0.011)) + (bassPulse * 0.006)))); value33.maskFilter = MaskFilter.blur(BlurStyle.normal, (14.0 + (p * 9.0))) }
canvas.drawPath(path, glowStroke)
_ = neonApply(crispStroke) { value34 in value34.color = Colors.white.withValues(alpha: ((0.025 + (shimmer * 0.030)) + (highPulse * 0.055))); value34.strokeWidth = (0.55 + (highPulse * 0.45)); value34.maskFilter = nil }
canvas.drawPath(path, crispStroke)
i += 1.0
}
}
let fillPaint = neonApply(Paint()) { value35 in value35.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 5.0) {
let r0 = (0.19 + (i * 0.135))
let r1 = ((r0 + 0.055) + (bassPulse * 0.006))
let c0 = (0.13 + (((Int(i) % 2 == 0) ? 0.04 : 0.17)))
let c1 = (c0 + 0.17)
let topA = _lerpOffset(_lerpOffset(outerTop, outerBottom, r0), _lerpOffset(innerTop, innerBottom, r0), c0)
let topB = _lerpOffset(_lerpOffset(outerTop, outerBottom, r0), _lerpOffset(innerTop, innerBottom, r0), c1)
let bottomA = _lerpOffset(_lerpOffset(outerTop, outerBottom, r1), _lerpOffset(innerTop, innerBottom, r1), c0)
let bottomB = _lerpOffset(_lerpOffset(outerTop, outerBottom, r1), _lerpOffset(innerTop, innerBottom, r1), c1)
let panel = _quadPath(topA, topB, bottomB, bottomA)
let bounds = panel.getBounds()
let color = Color.lerp(palette[Int(neonModulo(((i + (((side > 0.0) ? 1.0 : 0.0)))), Double(palette.count)))], Colors.white, 0.18)
_ = neonApply(fillPaint) { value36 in value36.shader = LinearGradient(begin: ((side < 0.0) ? Alignment.centerLeft : Alignment.centerRight), end: ((side < 0.0) ? Alignment.centerRight : Alignment.centerLeft), colors: [color.withValues(alpha: (0.030 + (midPulse * 0.035))), color.withValues(alpha: (0.115 + (highPulse * 0.060))), Colors.transparent]).createShader(bounds); value36.maskFilter = MaskFilter.blur(BlurStyle.normal, 9.0) }
canvas.drawPath(panel, fillPaint)
i += 1.0
}
}
}
let runwayPaint = neonApply(Paint()) { value37 in value37.style = PaintingStyle.stroke; value37.strokeCap = StrokeCap.round; value37.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 5.0) {
let p = (i / 4.0)
let y = (size.height * ((0.54 + (p * 0.23))))
let spread = (size.width * ((0.18 + (p * 0.39))))
let path = neonApply(Path()) { value38 in value38.moveTo((vp.dx - spread), y); value38.quadraticBezierTo(vp.dx, (y + (size.height * ((0.020 + (p * 0.020))))), (vp.dx + spread), y) }
_ = neonApply(runwayPaint) { value39 in value39.color = Color.lerp(palette[Int(1.0)], palette[Int(0.0)], p).withValues(alpha: ((0.040 + (midPulse * 0.052)) + (bassPulse * 0.030))); value39.strokeWidth = ((2.0 + (p * 5.0)) + (bassPulse * 3.0)); value39.maskFilter = MaskFilter.blur(BlurStyle.normal, (11.0 + (p * 8.0))) }
canvas.drawPath(path, runwayPaint)
_ = neonApply(runwayPaint) { value40 in value40.color = Colors.white.withValues(alpha: (0.018 + (highPulse * 0.030))); value40.strokeWidth = (0.55 + (p * 0.35)); value40.maskFilter = nil }
canvas.drawPath(path, runwayPaint)
i += 1.0
}
}
}

func _drawSpeakerStacks(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let paint = Paint()
for side in [-(1.0), 1.0] {
let centerX = (vp.dx + ((side * size.width) * 0.26))
let top = (size.height * 0.585)
let stackRect = Rect.fromCenter(center: Offset(centerX, (top + (size.height * 0.095))), width: (size.width * 0.105), height: (size.height * 0.19))
let rrect = RRect.fromRectAndRadius(stackRect, Radius.circular(12.0))
canvas.drawRRect(rrect, neonApply(Paint()) { value41 in value41.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF111116), Color(0xFF030306), Color.lerp(Color(0xFF050507), palette[Int(1.0)], 0.06)]).createShader(stackRect) })
canvas.drawRRect(rrect, neonApply(Paint()) { value42 in value42.style = PaintingStyle.stroke; value42.strokeWidth = 1.0; value42.color = Colors.white.withValues(alpha: (0.06 + (midPulse * 0.04))) })
do {
var i = 0.0
while (i < 2.0) {
let speakerCenter = Offset(centerX, (stackRect.top + (stackRect.height * ((0.31 + (i * 0.38))))))
let radius = (stackRect.width * ((0.22 + (bassPulse * 0.035))))
_ = neonApply(paint) { value43 in value43.shader = RadialGradient(colors: [Colors.black.withValues(alpha: 0.96), Color(0xFF12121A), Colors.black]).createShader(Rect.fromCircle(center: speakerCenter, radius: radius)) }
canvas.drawCircle(speakerCenter, radius, paint)
canvas.drawCircle(speakerCenter, (radius * ((1.30 + (bassPulse * 0.12)))), neonApply(Paint()) { value44 in value44.style = PaintingStyle.stroke; value44.strokeWidth = (1.2 + (bassPulse * 1.8)); value44.color = palette[Int(neonModulo(((i + (((side > 0.0) ? 1.0 : 0.0)))), Double(palette.count)))].withValues(alpha: (0.13 + (bassPulse * 0.16))); value44.maskFilter = MaskFilter.blur(BlurStyle.normal, (4.0 + (bassPulse * 6.0))); value44.blendMode = BlendMode.plus })
canvas.drawCircle(speakerCenter, (radius * 0.26), neonApply(Paint()) { value45 in value45.color = Colors.white.withValues(alpha: (0.04 + (bassPulse * 0.06))); value45.blendMode = BlendMode.plus })
i += 1.0
}
}
}
}

func _drawCeilingRig(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ highPulse: Double) -> Void {
let railPaint = neonApply(Paint()) { value46 in value46.style = PaintingStyle.stroke; value46.strokeCap = StrokeCap.round; value46.color = Colors.white.withValues(alpha: (0.13 + (highPulse * 0.10))); value46.strokeWidth = 1.2 }
do {
var i = 0.0
while (i < 5.0) {
let y = (size.height * ((0.115 + (i * 0.037))))
let spread = (size.width * ((0.34 + (i * 0.035))))
canvas.drawLine(Offset((vp.dx - spread), y), Offset((vp.dx + spread), y), railPaint)
i += 1.0
}
}
do {
var i = 0.0
while (i < 9.0) {
let x = (size.width * ((0.14 + (i * 0.09))))
let y = (size.height * ((0.12 + ((neonModulo(i, 3.0)) * 0.03))))
let pulse = (((sin((((t * Double.pi) * 2.0) + (i * 0.9))) + 1.0)) * 0.5)
let color = palette[Int(neonModulo(i, Double(palette.count)))]
let radius = (size.shortestSide * ((0.012 + (bassPulse * 0.004))))
canvas.drawCircle(Offset(x, y), (radius * ((4.0 + (highPulse * 2.0)))), neonApply(Paint()) { value47 in value47.shader = RadialGradient(colors: [color.withValues(alpha: ((0.22 + (pulse * 0.12)) + (highPulse * 0.10))), Colors.transparent]).createShader(Rect.fromCircle(center: Offset(x, y), radius: (radius * 5.6))); value47.blendMode = BlendMode.plus })
canvas.drawCircle(Offset(x, y), radius, neonApply(Paint()) { value48 in value48.color = Colors.white.withValues(alpha: (0.38 + (pulse * 0.24))); value48.blendMode = BlendMode.plus })
i += 1.0
}
}
}

func _drawReflectiveFloor(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let topY = (vp.dy + (size.height * 0.10))
let floorPath = neonApply(Path()) { value49 in value49.moveTo((vp.dx - (size.width * 0.16)), topY); value49.lineTo((vp.dx + (size.width * 0.16)), topY); value49.lineTo((size.width * 1.12), (size.height * 1.08)); value49.lineTo((-(size.width) * 0.12), (size.height * 1.08)); value49.close() }
canvas.drawPath(floorPath, neonApply(Paint()) { value50 in value50.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: (0.040 + (bassPulse * 0.025))), palette[Int(1.0)].withValues(alpha: (0.075 + (midPulse * 0.055))), Colors.black.withValues(alpha: 0.58)]).createShader(floorPath.getBounds()) })
let linePaint = neonApply(Paint()) { value51 in value51.style = PaintingStyle.stroke; value51.strokeCap = StrokeCap.round; value51.blendMode = BlendMode.plus }
do {
var i = -(7.0)
while (i <= 7.0) {
let amount = (i / 7.0)
let color = Color.lerp(palette[Int(1.0)], palette[Int(0.0)], (((amount + 1.0)) / 2.0))
let end = Offset((size.width * ((0.5 + (amount * 0.78)))), (size.height * 1.08))
_ = neonApply(linePaint) { value52 in value52.color = color.withValues(alpha: (0.12 + (bassPulse * 0.11))); value52.strokeWidth = (1.0 + (bassPulse * 1.2)); value52.maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0) }
canvas.drawLine(vp.translate(((amount * size.width) * 0.035), (size.height * 0.08)), end, linePaint)
_ = neonApply(linePaint) { value53 in value53.color = color.withValues(alpha: (0.22 + (bassPulse * 0.13))); value53.strokeWidth = 0.55; value53.maskFilter = nil }
canvas.drawLine(vp.translate(((amount * size.width) * 0.035), (size.height * 0.08)), end, linePaint)
i += 1.0
}
}
do {
var i = 0.0
while (i < 18.0) {
let raw = neonModulo(((((i / 18.0)) + (t * ((0.11 + (midPulse * 0.09)))))), 1.0)
let depth = (raw * raw)
let y = (topY + ((depth * size.height) * 0.78))
let spread = (size.width * ((0.13 + (depth * 0.83))))
let alpha = neonClamp((((0.06 + (depth * 0.18)) + (bassPulse * 0.11))), 0.0, 0.38)
_ = neonApply(linePaint) { value54 in value54.color = Colors.white.withValues(alpha: alpha); value54.strokeWidth = (0.8 + (depth * 2.1)); value54.maskFilter = MaskFilter.blur(BlurStyle.normal, (2.0 + (depth * 8.0))) }
canvas.drawLine(Offset((vp.dx - spread), y), Offset((vp.dx + spread), y), linePaint)
i += 1.0
}
}
}

func _drawStageCore(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ idleGlow: Double, _ bassPulse: Double, _ beatPulse: Double) -> Void {
let core = vp.translate(0.0, (size.height * 0.18))
let boothRect = Rect.fromCenter(center: core.translate(0.0, (size.height * 0.045)), width: (size.width * ((0.34 + (bassPulse * 0.018)))), height: (size.height * 0.060))
let haloRadius = (size.shortestSide * (((0.20 + (bassPulse * 0.055)) + (beatPulse * 0.035))))
canvas.drawCircle(core, haloRadius, neonApply(Paint()) { value55 in value55.shader = RadialGradient(colors: [Colors.white.withValues(alpha: (0.24 + (beatPulse * 0.10))), palette[Int(1.0)].withValues(alpha: (0.26 + (bassPulse * 0.12))), palette[Int(0.0)].withValues(alpha: 0.09), Colors.transparent]).createShader(Rect.fromCircle(center: core, radius: haloRadius)); value55.blendMode = BlendMode.plus })
let ringPaint = neonApply(Paint()) { value56 in value56.style = PaintingStyle.stroke; value56.strokeWidth = (2.2 + (bassPulse * 3.4)); value56.strokeCap = StrokeCap.round; value56.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 3.0) {
let rect = Rect.fromCenter(center: core, width: (size.width * (((0.16 + (i * 0.08)) + (bassPulse * 0.03)))), height: (size.height * (((0.055 + (i * 0.026)) + (bassPulse * 0.018)))))
_ = neonApply(ringPaint) { value57 in value57.color = palette[Int(i)].withValues(alpha: (((0.32 - (i * 0.045)) + (idleGlow * 0.10)) + (bassPulse * 0.13))); value57.maskFilter = MaskFilter.blur(BlurStyle.normal, (8.0 + (i * 8.0))) }
canvas.drawOval(rect, ringPaint)
i += 1.0
}
}
let prismCenter = core.translate(0.0, (size.height * 0.010))
let prism = neonApply(Path()) { value58 in value58.moveTo(prismCenter.dx, (prismCenter.dy - (size.height * 0.030))); value58.lineTo((prismCenter.dx + (size.width * 0.030)), prismCenter.dy); value58.lineTo(prismCenter.dx, (prismCenter.dy + (size.height * 0.036))); value58.lineTo((prismCenter.dx - (size.width * 0.030)), prismCenter.dy); value58.close() }
canvas.drawPath(prism, neonApply(Paint()) { value59 in value59.shader = RadialGradient(center: Alignment(-(0.2), -(0.35)), radius: 0.85, colors: [Colors.white.withValues(alpha: (0.20 + (beatPulse * 0.10))), palette[Int(1.0)].withValues(alpha: (0.24 + (bassPulse * 0.12))), palette[Int(0.0)].withValues(alpha: (0.10 + (idleGlow * 0.08))), Colors.transparent]).createShader(prism.getBounds()); value59.blendMode = BlendMode.plus; value59.maskFilter = MaskFilter.blur(BlurStyle.normal, (9.0 + (bassPulse * 8.0))) })
canvas.drawPath(prism, neonApply(Paint()) { value60 in value60.style = PaintingStyle.stroke; value60.strokeWidth = (0.9 + (bassPulse * 0.8)); value60.color = Colors.white.withValues(alpha: (0.18 + (bassPulse * 0.10))); value60.blendMode = BlendMode.plus })
canvas.drawRRect(RRect.fromRectAndRadius(boothRect, Radius.circular(10.0)), neonApply(Paint()) { value61 in value61.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF07070A), Color.lerp(Color(0xFF1A1B26), palette[Int(1.0)], 0.14), Color.lerp(Color(0xFF111118), palette[Int(0.0)], 0.08), Color(0xFF050507)], stops: [0.0, 0.34, 0.70, 1.0]).createShader(boothRect) })
canvas.drawRRect(RRect.fromRectAndRadius(boothRect.deflate(1.0), Radius.circular(9.0)), neonApply(Paint()) { value62 in value62.style = PaintingStyle.stroke; value62.strokeWidth = 1.1; value62.color = Colors.white.withValues(alpha: (0.20 + (beatPulse * 0.11))) })
let ledStrip = Rect.fromLTWH((boothRect.left + (boothRect.width * 0.10)), (boothRect.top + (boothRect.height * 0.46)), (boothRect.width * 0.80), (2.0 + (bassPulse * 3.0)))
canvas.drawRRect(RRect.fromRectAndRadius(ledStrip, Radius.circular(999.0)), neonApply(Paint()) { value63 in value63.shader = LinearGradient(colors: [palette[Int(0.0)], Colors.white, palette[Int(1.0)], palette[Int(2.0)]]).createShader(ledStrip); value63.blendMode = BlendMode.plus; value63.maskFilter = MaskFilter.blur(BlurStyle.normal, (5.0 + (bassPulse * 7.0))) })
let deckPaint = neonApply(Paint()) { value64 in value64.blendMode = BlendMode.plus }
for side in [-(1.0), 1.0] {
let deckCenter = Offset((boothRect.center.dx + ((side * boothRect.width) * 0.285)), (boothRect.center.dy + (boothRect.height * 0.03)))
let deckRadius = (boothRect.height * ((0.24 + (bassPulse * 0.028))))
canvas.drawCircle(deckCenter, (deckRadius * 1.7), neonApply(Paint()) { value65 in value65.shader = RadialGradient(colors: [palette[Int(((side < 0.0) ? 0.0 : 1.0))].withValues(alpha: (0.12 + (bassPulse * 0.09))), Colors.transparent]).createShader(Rect.fromCircle(center: deckCenter, radius: (deckRadius * 1.8))); value65.blendMode = BlendMode.plus })
canvas.drawCircle(deckCenter, deckRadius, neonApply(Paint()) { value66 in value66.shader = RadialGradient(colors: [Color(0xFF1C1D25), Colors.black.withValues(alpha: 0.95)]).createShader(Rect.fromCircle(center: deckCenter, radius: deckRadius)) })
canvas.drawCircle(deckCenter, (deckRadius * 0.35), neonApply(Paint()) { value67 in value67.color = Colors.white.withValues(alpha: (0.08 + (bassPulse * 0.08))); value67.blendMode = BlendMode.plus })
canvas.drawArc(Rect.fromCircle(center: deckCenter, radius: (deckRadius * 0.78)), (((t * Double.pi) * 2.0) * side), (Double.pi * ((0.58 + (bassPulse * 0.28)))), false, neonApply(deckPaint) { value68 in value68.style = PaintingStyle.stroke; value68.strokeWidth = 1.0; value68.strokeCap = StrokeCap.round; value68.color = palette[Int(((side < 0.0) ? 0.0 : 1.0))].withValues(alpha: (0.34 + (bassPulse * 0.18))); value68.maskFilter = nil })
}
do {
var i = 0.0
while (i < 9.0) {
let p = (i / 8.0)
let x = (boothRect.left + (boothRect.width * ((0.20 + (p * 0.60)))))
let y = (boothRect.top + (boothRect.height * 0.25))
let color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.18)
canvas.drawCircle(Offset(x, y), (1.2 + (bassPulse * 1.2)), neonApply(Paint()) { value69 in value69.color = color.withValues(alpha: (0.28 + (bassPulse * 0.22))); value69.blendMode = BlendMode.plus; value69.maskFilter = MaskFilter.blur(BlurStyle.normal, (2.0 + (bassPulse * 3.0))) })
i += 1.0
}
}
}

func _drawTopLightCones(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ highPulse: Double) -> Void {
let paint = neonApply(Paint()) { value70 in value70.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 6.0) {
let side = ((Int(i) % 2 == 0) ? -(1.0) : 1.0)
let source = Offset((size.width * ((0.16 + (i * 0.135)))), (size.height * ((0.135 + ((neonModulo(i, 2.0)) * 0.035)))))
let sweep = ((sin((((t * Double.pi) * 2.0) + (i * 0.74))) * size.width) * 0.13)
let target = Offset(((vp.dx + sweep) + ((side * size.width) * 0.05)), (size.height * ((0.68 + ((neonModulo(i, 3.0)) * 0.035)))))
let width = (size.width * ((0.09 + (highPulse * 0.045))))
let cone = neonApply(Path()) { value71 in value71.moveTo((source.dx - (size.width * 0.010)), source.dy); value71.lineTo((target.dx - width), target.dy); value71.quadraticBezierTo(target.dx, (target.dy + (size.height * 0.035)), (target.dx + width), target.dy); value71.lineTo((source.dx + (size.width * 0.010)), source.dy); value71.close() }
let color = palette[Int(neonModulo(((i + 1.0)), Double(palette.count)))]
_ = neonApply(paint) { value72 in value72.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: (0.16 + (highPulse * 0.12))), color.withValues(alpha: (0.052 + (bassPulse * 0.05))), Colors.transparent]).createShader(cone.getBounds()); value72.maskFilter = MaskFilter.blur(BlurStyle.normal, (18.0 + (highPulse * 18.0))) }
canvas.drawPath(cone, paint)
i += 1.0
}
}
}

func _drawNeonTubeFrame(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let glow = neonApply(Paint()) { value73 in value73.style = PaintingStyle.stroke; value73.strokeCap = StrokeCap.round; value73.strokeJoin = StrokeJoin.round; value73.blendMode = BlendMode.plus }
let core = neonApply(Paint()) { value74 in value74.style = PaintingStyle.stroke; value74.strokeCap = StrokeCap.round; value74.strokeJoin = StrokeJoin.round; value74.blendMode = BlendMode.plus }
let portalCenter = vp.translate(0.0, (size.height * 0.23))
do {
var i = 0.0
while (i < 5.0) {
let depth = (i / 4.0)
let rect = Rect.fromCenter(center: portalCenter.translate(0.0, (size.height * ((0.030 + (depth * 0.055))))), width: (size.width * (((0.36 + (depth * 0.50)) + (bassPulse * 0.050)))), height: (size.height * (((0.10 + (depth * 0.25)) + (bassPulse * 0.030)))))
let color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.13)
let start = (-(Double.pi) * ((0.94 + (sin((((t * Double.pi) * 2.0) + i)) * 0.025))))
let sweep = (Double.pi * ((0.88 + (midPulse * 0.16))))
_ = neonApply(glow) { value75 in value75.color = color.withValues(alpha: (((0.10 + (midPulse * 0.11)) + (highPulse * 0.06)) - (depth * 0.018))); value75.strokeWidth = ((8.0 + (bassPulse * 8.0)) + (depth * 3.0)); value75.maskFilter = MaskFilter.blur(BlurStyle.normal, (18.0 + (depth * 12.0))) }
canvas.drawArc(rect, start, sweep, false, glow)
_ = neonApply(core) { value76 in value76.color = Colors.white.withValues(alpha: ((0.080 + (highPulse * 0.10)) + (bassPulse * 0.040))); value76.strokeWidth = (0.80 + (bassPulse * 0.70)); value76.maskFilter = nil }
canvas.drawArc(rect, start, sweep, false, core)
i += 1.0
}
}
for side in [-(1.0), 1.0] {
do {
var i = 0.0
while (i < 4.0) {
let depth = (i / 3.0)
let top = Offset((vp.dx + ((side * size.width) * ((0.18 + (depth * 0.17))))), (size.height * ((0.28 + (depth * 0.055)))))
let bottom = Offset((vp.dx + ((side * size.width) * ((0.30 + (depth * 0.35))))), (size.height * ((0.86 + (depth * 0.025)))))
let control = Offset((vp.dx + ((side * size.width) * ((0.34 + (depth * 0.20))))), (size.height * ((0.55 + (sin((((t * Double.pi) * 2.0) + i)) * 0.015)))))
let path = neonApply(Path()) { value77 in value77.moveTo(top.dx, top.dy); value77.quadraticBezierTo(control.dx, control.dy, bottom.dx, bottom.dy) }
let color = Color.lerp(palette[Int(neonModulo(((i + (((side > 0.0) ? 1.0 : 2.0)))), Double(palette.count)))], Colors.white, 0.10)
let alpha = ((0.075 + (midPulse * 0.090)) + (highPulse * 0.070))
_ = neonApply(glow) { value78 in value78.color = color.withValues(alpha: alpha); value78.strokeWidth = (size.width * (((0.020 + (depth * 0.012)) + (bassPulse * 0.008)))); value78.maskFilter = MaskFilter.blur(BlurStyle.normal, (15.0 + (depth * 10.0))) }
canvas.drawPath(path, glow)
_ = neonApply(core) { value79 in value79.color = Colors.white.withValues(alpha: (0.045 + (highPulse * 0.08))); value79.strokeWidth = (0.7 + (bassPulse * 0.65)); value79.maskFilter = nil }
canvas.drawPath(path, core)
i += 1.0
}
}
}
do {
var i = -(5.0)
while (i <= 5.0) {
let amount = (i / 5.0)
let start = vp.translate(((amount * size.width) * 0.045), (size.height * 0.13))
let end = Offset((size.width * ((0.5 + (amount * 0.62)))), (size.height * 0.91))
let color = Color.lerp(palette[Int(1.0)], palette[Int(0.0)], (((amount + 1.0)) / 2.0))
_ = neonApply(glow) { value80 in value80.color = color.withValues(alpha: (0.040 + (bassPulse * 0.060))); value80.strokeWidth = (4.5 + (bassPulse * 4.0)); value80.maskFilter = MaskFilter.blur(BlurStyle.normal, 16.0) }
canvas.drawLine(start, end, glow)
_ = neonApply(core) { value81 in value81.color = Colors.white.withValues(alpha: (0.018 + (bassPulse * 0.045))); value81.strokeWidth = 0.55; value81.maskFilter = nil }
canvas.drawLine(start, end, core)
i += 1.0
}
}
}

func _drawFloorGloss(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let floorTop = (vp.dy + (size.height * 0.16))
let paint = neonApply(Paint()) { value82 in value82.style = PaintingStyle.stroke; value82.strokeCap = StrokeCap.round; value82.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 8.0) {
let depth = (i / 7.0)
let y = (floorTop + ((pow(depth, 1.55) * size.height) * 0.62))
let spread = (size.width * ((0.12 + (depth * 0.52))))
let phase = (((t * Double.pi) * 2.0) + (i * 0.67))
let start = Offset((vp.dx - spread), (y + ((sin(phase) * size.height) * 0.008)))
let end = Offset((vp.dx + spread), (y + ((cos(phase) * size.height) * 0.008)))
let color = Color.lerp(palette[Int(1.0)], palette[Int(0.0)], depth)
_ = neonApply(paint) { value83 in value83.color = color.withValues(alpha: ((0.070 + (midPulse * 0.070)) + (depth * 0.020))); value83.strokeWidth = ((2.0 + (depth * 6.0)) + (bassPulse * 3.0)); value83.maskFilter = MaskFilter.blur(BlurStyle.normal, (10.0 + (depth * 12.0))) }
canvas.drawLine(start, end, paint)
_ = neonApply(paint) { value84 in value84.color = Colors.white.withValues(alpha: (0.030 + (bassPulse * 0.035))); value84.strokeWidth = (0.55 + (depth * 0.65)); value84.maskFilter = nil }
canvas.drawLine(start, end, paint)
i += 1.0
}
}
let reflectionCenter = Offset(vp.dx, (size.height * 0.74))
canvas.drawOval(Rect.fromCenter(center: reflectionCenter, width: (size.width * ((0.54 + (bassPulse * 0.06)))), height: (size.height * ((0.19 + (bassPulse * 0.035))))), neonApply(Paint()) { value85 in value85.shader = RadialGradient(colors: [palette[Int(1.0)].withValues(alpha: (0.16 + (midPulse * 0.10))), palette[Int(0.0)].withValues(alpha: (0.06 + (bassPulse * 0.06))), Colors.transparent]).createShader(Rect.fromCenter(center: reflectionCenter, width: (size.width * 0.60), height: (size.height * 0.22))); value85.blendMode = BlendMode.plus })
}

func _drawArchitecturalRings(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double) -> Void {
let paint = neonApply(Paint()) { value86 in value86.style = PaintingStyle.stroke; value86.strokeCap = StrokeCap.round; value86.blendMode = BlendMode.plus }
let center = vp.translate(0.0, (size.height * 0.21))
do {
var i = 0.0
while (i < 5.0) {
let rect = Rect.fromCenter(center: center.translate(0.0, (size.height * ((0.012 * i)))), width: (size.width * (((0.42 + (i * 0.12)) + (bassPulse * 0.035)))), height: (size.height * (((0.13 + (i * 0.058)) + (bassPulse * 0.018)))))
let start = (-(Double.pi) * ((0.93 + (sin((((t * Double.pi) * 2.0) + i)) * 0.04))))
let sweep = (Double.pi * ((0.86 + (midPulse * 0.14))))
let color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.08)
_ = neonApply(paint) { value87 in value87.color = color.withValues(alpha: ((0.075 + (midPulse * 0.050)) - (i * 0.006))); value87.strokeWidth = (1.3 + (bassPulse * 2.2)); value87.maskFilter = MaskFilter.blur(BlurStyle.normal, (6.0 + (i * 3.0))) }
canvas.drawArc(rect, start, sweep, false, paint)
_ = neonApply(paint) { value88 in value88.color = Colors.white.withValues(alpha: (0.035 + (bassPulse * 0.025))); value88.strokeWidth = 0.55; value88.maskFilter = nil }
canvas.drawArc(rect, start, sweep, false, paint)
i += 1.0
}
}
}

func _drawLensBloom(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let paint = neonApply(Paint()) { value89 in value89.blendMode = BlendMode.plus }
let centers = [vp.translate((-(size.width) * 0.22), (size.height * 0.22)), vp.translate((size.width * 0.22), (size.height * 0.23)), vp.translate(0.0, (size.height * 0.32))]
do {
var i = 0.0
while (i < Double(centers.count)) {
let c = centers[Int(i)].translate(((sin((((t * Double.pi) * 2.0) + i)) * size.width) * 0.018), ((cos((((t * Double.pi) * 2.0) + (i * 0.7))) * size.height) * 0.012))
let radius = (size.shortestSide * (((0.11 + (i * 0.035)) + (bassPulse * 0.025))))
let color = palette[Int(neonModulo(((i + 1.0)), Double(palette.count)))]
_ = neonApply(paint) { value90 in value90.shader = RadialGradient(colors: [Colors.white.withValues(alpha: (0.055 + (highPulse * 0.055))), color.withValues(alpha: (0.090 + (midPulse * 0.075))), Colors.transparent]).createShader(Rect.fromCircle(center: c, radius: radius)); value90.maskFilter = MaskFilter.blur(BlurStyle.normal, (10.0 + (bassPulse * 12.0))) }
canvas.drawCircle(c, radius, paint)
i += 1.0
}
}
}

func _drawEmbeddedSpectrum(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let spectrum = frame.spectrum
if spectrum.isEmpty { return }
let bins = 34.0
let binsPerBar = max(1.0, ((Double(spectrum.count) / bins).rounded(.towardZero)))
let paint = neonApply(Paint()) { value91 in value91.blendMode = BlendMode.plus }
for side in [-(1.0), 1.0] {
do {
var i = 0.0
while (i < bins) {
var sum = 0.0
let start = (i * binsPerBar)
do {
var j = start
while ((j < (start + binsPerBar)) && (j < Double(spectrum.count))) {
sum += spectrum[Int(j)]
j += 1.0
}
}
let rawValue = neonClamp(((sum / binsPerBar)), 0.0, 1.0)
let weighted = neonClamp((((((rawValue * 0.7) + (bassPulse * 0.11)) + (midPulse * 0.11)) + (highPulse * 0.08))), 0.02, 1.0)
let column = (i / bins)
let y = (size.height * ((0.31 + (column * 0.34))))
let wallDepth = (column * column)
let x = (vp.dx + ((side * size.width) * ((0.21 + (wallDepth * 0.26)))))
let barLength = ((size.width * ((0.02 + (weighted * 0.11)))) * side)
let color = Color.lerp(palette[Int(1.0)], palette[Int(0.0)], column)
let rect = Rect.fromCenter(center: Offset((x + (barLength * 0.5)), y), width: abs(barLength), height: (2.0 + (weighted * 3.4)))
_ = neonApply(paint) { value92 in value92.shader = LinearGradient(colors: [color.withValues(alpha: 0.0), color.withValues(alpha: (0.28 + (weighted * 0.36))), Colors.white.withValues(alpha: (0.08 + (weighted * 0.18)))]).createShader(rect); value92.maskFilter = MaskFilter.blur(BlurStyle.normal, (4.0 + (weighted * 6.0))) }
canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(999.0)), paint)
i += 1.0
}
}
}
}

func _drawLaserRibbons(_ canvas: Canvas, _ size: Size, _ vp: Offset, _ t: Double, _ beatPulse: Double, _ highPulse: Double) -> Void {
if ((beatPulse + highPulse) < 0.03) { return }
let count = (3.0 + ((highPulse * 5.0)).rounded(.toNearestOrAwayFromZero))
let paint = neonApply(Paint()) { value93 in value93.style = PaintingStyle.stroke; value93.strokeCap = StrokeCap.round; value93.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < count) {
let side = ((Int(i) % 2 == 0) ? -(1.0) : 1.0)
let phase = (((t * Double.pi) * 2.0) + (i * 1.43))
let start = Offset(((side < 0.0) ? (-(size.width) * 0.03) : (size.width * 1.03)), (size.height * (((0.20 + (i * 0.055)) + (sin(phase) * 0.035)))))
let end = Offset(((side < 0.0) ? (size.width * 1.04) : (-(size.width) * 0.04)), (size.height * (((0.30 + ((neonModulo(i, 4.0)) * 0.115)) + (cos(phase) * 0.04)))))
let controlA = vp.translate(((side * size.width) * ((0.24 + (sin(phase) * 0.05)))), (size.height * ((0.02 + (i * 0.035)))))
let controlB = vp.translate(((-(side) * size.width) * ((0.30 + (cos(phase) * 0.06)))), (size.height * ((0.21 + (i * 0.045)))))
let path = neonApply(Path()) { value94 in value94.moveTo(start.dx, start.dy); value94.cubicTo(controlA.dx, controlA.dy, controlB.dx, controlB.dy, end.dx, end.dy) }
let color = palette[Int(neonModulo(i, Double(palette.count)))]
let alpha = neonClamp((((0.10 + (highPulse * 0.35)) + (beatPulse * 0.18))), 0.0, 0.62)
_ = neonApply(paint) { value95 in value95.color = color.withValues(alpha: alpha); value95.strokeWidth = (5.0 + (highPulse * 6.0)); value95.maskFilter = MaskFilter.blur(BlurStyle.normal, (14.0 + (highPulse * 14.0))) }
canvas.drawPath(path, paint)
_ = neonApply(paint) { value96 in value96.color = Colors.white.withValues(alpha: neonClamp((((0.12 + (highPulse * 0.22)) + (beatPulse * 0.18))), 0.0, 0.5)); value96.strokeWidth = (0.85 + (highPulse * 1.1)); value96.maskFilter = nil }
canvas.drawPath(path, paint)
i += 1.0
}
}
}

func _drawAtmosphericDust(_ canvas: Canvas, _ size: Size, _ t: Double, _ highPulse: Double, _ midPulse: Double) -> Void {
let paint = neonApply(Paint()) { value97 in value97.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < Double(Self.particles.count)) {
let seed = Self.particles[Int(i)]
let depth = (0.35 + (seed.y * 0.9))
let drift = (((sin((((t * Double.pi) * 2.0) + seed.phase)) * 0.026) * motion) * depth)
let rise = neonModulo((((t * 0.035) * seed.speed)), 1.0)
let x = ((neonModulo(((seed.x + drift)), 1.0)) * size.width)
let y = ((neonModulo(((seed.y + rise)), 1.0)) * size.height)
let shimmer = (((sin((((t * Double.pi) * 10.0) + seed.phase)) + 1.0)) * 0.5)
let alpha = neonClamp((((0.028 + (shimmer * 0.050)) + (highPulse * 0.18))), 0.0, 0.32)
let radius = (seed.speed * (((0.55 + (highPulse * 1.9)) + (midPulse * 0.45))))
paint.color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.22).withValues(alpha: alpha)
canvas.drawCircle(Offset(x, y), radius, paint)
i += 1.0
}
}
}

func _drawForegroundEnergy(_ canvas: Canvas, _ size: Size, _ t: Double, _ bassPulse: Double, _ midPulse: Double, _ highPulse: Double) -> Void {
let baseY = (size.height * 0.91)
let silhouettePaint = neonApply(Paint()) { value98 in value98.color = Colors.black.withValues(alpha: 0.70) }
let glowPaint = neonApply(Paint()) { value99 in value99.blendMode = BlendMode.plus }
let silhouette = neonApply(Path()) { value100 in value100.moveTo(0.0, size.height) }
do {
var i = 0.0
while (i <= 28.0) {
let p = (i / 28.0)
let x = (size.width * p)
let wave = ((sin((((p * Double.pi) * 8.0) + ((t * Double.pi) * 2.0))) * size.height) * 0.006)
let shoulder = ((pow(sin((p * Double.pi)), 0.7) * size.height) * ((0.018 + (bassPulse * 0.015))))
let y = ((baseY - shoulder) + wave)
silhouette.lineTo(x, y)
i += 1.0
}
}
_ = neonApply(silhouette) { value101 in value101.lineTo(size.width, size.height); value101.close() }
canvas.drawPath(silhouette, silhouettePaint)
let bodyPaint = neonApply(Paint()) { value102 in value102.color = Colors.black.withValues(alpha: 0.78) }
let edgeGlow = neonApply(Paint()) { value103 in value103.blendMode = BlendMode.plus }
do {
var i = 0.0
while (i < 24.0) {
let p = ((((i + 0.35) + (sin((i * 7.1)) * 0.08))) / 24.0)
let x = (size.width * p)
let phase = (((t * Double.pi) * 2.0) + (i * 0.63))
let height = (size.height * ((0.030 + ((abs(sin((i * 1.7)))) * 0.026))))
let bob = ((sin(phase) * size.height) * ((0.004 + (bassPulse * 0.005))))
let headCenter = Offset(x, (((baseY - height) - (size.height * 0.014)) + bob))
let headRadius = (size.width * ((0.010 + ((neonModulo(i, 3.0)) * 0.002))))
canvas.drawCircle(headCenter, headRadius, bodyPaint)
let bodyRect = Rect.fromCenter(center: Offset(x, ((baseY - (height * 0.44)) + bob)), width: (size.width * ((0.020 + ((neonModulo(i, 4.0)) * 0.004)))), height: height)
canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, Radius.circular((size.width * 0.018))), bodyPaint)
if ((neonModulo(i, 5.0) == 0.0) || (((bassPulse > 0.35) && (neonModulo(i, 4.0) == 0.0)))) {
let armColor = palette[Int(neonModulo(i, Double(palette.count)))]
let armTop = headCenter.translate(((sin((phase * 1.2)) * size.width) * 0.012), (-(size.height) * ((0.030 + (bassPulse * 0.018)))))
let armPath = neonApply(Path()) { value104 in value104.moveTo((x - (size.width * 0.006)), (baseY - (height * 0.72))); value104.quadraticBezierTo((x + ((sin(phase) * size.width) * 0.025)), (baseY - (height * 1.12)), armTop.dx, armTop.dy) }
_ = neonApply(edgeGlow) { value105 in value105.color = armColor.withValues(alpha: (0.08 + (bassPulse * 0.08))); value105.strokeWidth = (1.2 + (bassPulse * 1.0)); value105.style = PaintingStyle.stroke; value105.strokeCap = StrokeCap.round; value105.maskFilter = MaskFilter.blur(BlurStyle.normal, (5.0 + (bassPulse * 5.0))) }
canvas.drawPath(armPath, edgeGlow)
}
i += 1.0
}
}
do {
var i = 0.0
while (i < 18.0) {
let p = (i / 17.0)
let x = (size.width * p)
let phase = (((t * Double.pi) * 2.0) + (i * 0.71))
let height = (size.height * (((0.016 + (bassPulse * 0.040)) + (abs(sin(phase)) * 0.012))))
let color = Color.lerp(palette[Int(neonModulo(i, Double(palette.count)))], Colors.white, 0.12)
let rect = Rect.fromCenter(center: Offset(x, (baseY - (height * 0.5))), width: (size.width * ((0.006 + (highPulse * 0.004)))), height: height)
_ = neonApply(glowPaint) { value106 in value106.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: (0.22 + (midPulse * 0.10))), color.withValues(alpha: 0.03), Colors.transparent]).createShader(rect); value106.maskFilter = MaskFilter.blur(BlurStyle.normal, (7.0 + (bassPulse * 7.0))) }
canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(999.0)), glowPaint)
i += 1.0
}
}
}

func _drawBeatFlash(_ canvas: Canvas, _ size: Size, _ beatPulse: Double, _ bassPulse: Double) -> Void {
if ((beatPulse + bassPulse) < 0.025) { return }
let alpha = neonClamp((((beatPulse * 0.12) + (bassPulse * 0.045))), 0.0, 0.18)
let center = Offset((size.width * 0.5), (size.height * 0.52))
canvas.drawRect((Offset.zero & size), neonApply(Paint()) { value107 in value107.shader = RadialGradient(colors: [Colors.white.withValues(alpha: alpha), palette[Int(1.0)].withValues(alpha: (alpha * 0.85)), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: (size.longestSide * 0.55))); value107.blendMode = BlendMode.plus })
}

func _drawVignette(_ canvas: Canvas, _ size: Size) -> Void {
canvas.drawRect((Offset.zero & size), neonApply(Paint()) { value108 in value108.shader = RadialGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.68)], stops: [0.44, 0.78, 1.0]).createShader((Offset.zero & size)) })
canvas.drawRect((Offset.zero & size), neonApply(Paint()) { value109 in value109.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, Colors.transparent, Colors.black54], stops: [0.0, 0.42, 1.0]).createShader((Offset.zero & size)) })
}

func _lerpOffset(_ a: Offset, _ b: Offset, _ t: Double) -> Offset {
return Offset.lerp(a, b, t)
}

func _quadPath(_ a: Offset, _ b: Offset, _ c: Offset, _ d: Offset) -> Path {
return neonApply(Path()) { value110 in value110.moveTo(a.dx, a.dy); value110.lineTo(b.dx, b.dy); value110.lineTo(c.dx, c.dy); value110.lineTo(d.dx, d.dy); value110.close() }
}
}
