import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // debugPrint, kDebugMode
import 'package:rotas_rurais/register.dart';
import 'package:rotas_rurais/servicos_publicos_page.dart';
import 'package:rotas_rurais/sobre.dart';
import 'package:url_launcher/url_launcher.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'busca_avancada_page.dart';
import 'corretorPage.dart';
import 'estatisticas_page.dart';
import 'firebase_options.dart';

// Plus Code
import 'package:open_location_code/open_location_code.dart' as olc;

// Datas para estatísticas
import 'package:intl/intl.dart';

// Compartilhamento
import 'package:share_plus/share_plus.dart';

// Logo animado
import 'logo_animado.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color kBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: kBlue,
      brightness: Brightness.light,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(fontSize: 16, color: Colors.black54),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kBlue,
          foregroundColor: Colors.white,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 1.5,
        margin: EdgeInsets.zero,
      ),
    );

    return MaterialApp(
      title: 'Rotas Rurais',
      theme: base,
      home: const LogoSplash(),
      routes: {
        '/home': (_) => const UpaHomePage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

/// =========================
/// SPLASH (3s)
/// =========================
class LogoSplash extends StatefulWidget {
  const LogoSplash({super.key});
  @override
  State<LogoSplash> createState() => _LogoSplashState();
}

class _LogoSplashState extends State<LogoSplash> {
  static const kLogoDuration = Duration(milliseconds: 3000);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(kLogoDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UpaHomePage()),
      );
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MyApp.kBlue,
      body: SafeArea(
        child: Center(child: LogoAnimadoPage()),
      ),
    );
  }
}

/// =========================
/// HOME
/// =========================
class UpaHomePage extends StatefulWidget {
  const UpaHomePage({super.key});
  @override
  State<UpaHomePage> createState() => _UpaHomePageState();
}

class _UpaHomePageState extends State<UpaHomePage> {
  final TextEditingController _buscaCtrl = TextEditingController();
  final DatabaseReference _ref = FirebaseDatabase.instance.ref('upas');

  /// evita registrar o mesmo termo várias vezes na mesma sessão
  final Set<String> _termosLogados = {};

  /// NEW: evita contar múltiplos acessos da mesma UPA na mesma sessão
  final Set<String> _rotasLogadas = {};

  @override
  void initState() {
    super.initState();

    // (Opcional) Diagnóstico rápido em debug para confirmar escrita/URL
    if (kDebugMode) {
      FirebaseDatabase.instance
          .ref('estatisticas/__health__/startup')
          .set(ServerValue.timestamp)
          .then((_) => debugPrint('startup ping OK'))
          .catchError((e) => debugPrint('startup ping FALHOU: $e'));
    }
  }

  void _limparBusca() {
    _buscaCtrl.clear();
    setState(() {});
  }

  UpaRecord? _upaFromMap(Map<dynamic, dynamic> raw) {
    final Map<String, dynamic> root = {};
    raw.forEach((k, v) => root[k.toString()] = v);

    final Map<String, dynamic> geom =
    (root['geometry'] is Map)
        ? (root['geometry'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    final attrs = <String, String>{};
    void addAll(Map<String, dynamic> m) {
      m.forEach((k, v) {
        if (v != null) attrs[k] = v.toString();
      });
    }
    addAll(root);
    addAll(geom);

    String? codigoUpa = (root['codigo_upa'] ??
        root['codigo UPA'] ??
        root['Código UPA'] ??
        geom['codigo_upa'])
        ?.toString();
    codigoUpa = (codigoUpa?.trim().isEmpty ?? true) ? null : codigoUpa!.trim();

    final nome =
    (root['nome_upa'] ?? geom['nome_upa'] ?? root['nome'] ?? geom['nome'])
        ?.toString();

    LatLng? coord;
    double? tryD(dynamic x) => x == null ? null : double.tryParse(x.toString());
    final lat = tryD(root['latitude'] ?? geom['latitude']);
    final lon = tryD(root['longitude'] ?? geom['longitude']);
    if (lat != null && lon != null) coord = LatLng(lat, lon);

    if (coord == null) {
      final plusRaw = obterPlusCode(attrs);
      final plus = sanitizePlusCode(plusRaw);
      final decoded = decodePlusAsLatLngIfGlobal(plus);
      if (decoded != null) coord = decoded;
    }

    return UpaRecord(
      codigoUpa: codigoUpa,
      nome: nome,
      coord: coord,
      atributos: attrs,
    );
  }

  /// =========================
  /// NEW: LOG DE ROTAS ACESSADAS
  /// =========================

  String _municipioDe(Map<String, String> attrs) {
    String? v;
    for (final k in const ['municipio', 'cidade', 'município']) {
      v ??= attrs.entries
          .firstWhere((e) => e.key.toLowerCase().trim() == k,
          orElse: () => const MapEntry('', ''))
          .value;
      if ((v ?? '').trim().isNotEmpty) break;
    }
    return (v ?? '').trim();
  }

  String _rotaKey(UpaRecord upa) {
    final c = (upa.codigoUpa ?? '').trim();
    if (c.isNotEmpty) return 'codigo:$c';

    final plus = (obterPlusCode(upa.atributos) ?? '').trim();
    if (plus.isNotEmpty) return 'plus:$plus';

    final n = (upa.nome ?? '').trim();
    if (n.isNotEmpty) return 'nome:$n';

    return 'hash:${upa.atributos.hashCode}';
  }

  Future<void> _incRota(String path) async {
    await FirebaseDatabase.instance.ref(path).set(ServerValue.increment(1));
  }

  Future<void> logAcessoRota({
    required UpaRecord upa,
    required String origem, // ex: 'home'
    String? via, // 'google_maps' | 'waze' | 'apple_maps' | 'navegador' | 'compartilhar'
  }) async {
    final key = _rotaKey(upa);
    final dia = _hoje();
    final muni = _municipioDe(upa.atributos);

    try {
      // totais globais
      await _incRota('estatisticas/rotas/totais/$dia');
      await _incRota('estatisticas/rotas/totalGeral');

      // por rota
      await _incRota('estatisticas/rotas/porRota/$key/$dia');
      await _incRota('estatisticas/rotas/porRota/$key/totalGeral');

      // por município (ranking agregado)
      if (muni.isNotEmpty) {
        await _incRota('estatisticas/rotas/porMunicipio/$muni/$dia');
        await _incRota('estatisticas/rotas/porMunicipio/$muni/totalGeral');
      }

      // origem e via
      await _incRota('estatisticas/rotas/origem/$origem/$dia');
      await _incRota('estatisticas/rotas/origem/$origem/totalGeral');

      if ((via ?? '').isNotEmpty) {
        await _incRota('estatisticas/rotas/via/$via/$dia');
        await _incRota('estatisticas/rotas/via/$via/totalGeral');
        await _incRota('estatisticas/rotas/porRotaVia/$key/$via/$dia');
        await _incRota('estatisticas/rotas/porRotaVia/$key/$via/totalGeral');
      }

      // último acesso (metadados úteis)
      await FirebaseDatabase.instance.ref('estatisticas/rotas/ultimo').set({
        'rotaKey': key,
        'codigo': upa.codigoUpa,
        'nome': upa.nome,
        'municipio': muni,
        'origem': origem,
        'via': via,
        'ts': ServerValue.timestamp,
      });
    } catch (e, s) {
      debugPrint('logAcessoRota falhou: $e\n$s');
    }
  }

  Future<void> _abrirEscolherApp(UpaRecord upa) async {
    final alvo = resolverAlvo(upa);
    final plusRaw = obterPlusCode(upa.atributos);
    final plus = sanitizePlusCode(plusRaw);

    if (alvo == null && plus == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem Plus Code ou coordenadas disponíveis.')),
      );
      return;
    }

    final nomeLocal = nomeParaExibir(upa);
    final label = Uri.encodeComponent(nomeLocal);

    Uri? urlGoogleMapsApp;
    Uri? urlWazeApp;
    Uri? urlAppleMaps;
    Uri? urlNavegador;

    if (alvo != null) {
      final lat = alvo.lat.toString();
      final lon = alvo.lon.toString();

      urlGoogleMapsApp = Platform.isIOS
          ? Uri.parse('comgooglemaps://?q=$lat,$lon&center=$lat,$lon&zoom=18')
          : Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)');

      urlWazeApp = Uri.parse('waze://?ll=$lat,$lon&navigate=yes');
      urlAppleMaps = Uri.parse('http://maps.apple.com/?ll=$lat,$lon&q=$label');
      urlNavegador =
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    } else {
      final qp = Uri.encodeComponent(plus!);
      urlGoogleMapsApp =
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$qp');
      urlNavegador = urlGoogleMapsApp;
      urlAppleMaps = Uri.parse('http://maps.apple.com/?q=$qp');
      urlWazeApp = null;
    }

    final List<_AbrirOpcao> opcoes = [];
    if (urlGoogleMapsApp != null && await canLaunchUrl(urlGoogleMapsApp)) {
      opcoes.add(_AbrirOpcao(nome: 'Google Maps', icone: Icons.map, uri: urlGoogleMapsApp));
    }
    if (urlWazeApp != null && await canLaunchUrl(urlWazeApp)) {
      opcoes.add(_AbrirOpcao(nome: 'Waze', icone: Icons.directions_car, uri: urlWazeApp));
    }
    if (Platform.isIOS && urlAppleMaps != null && await canLaunchUrl(urlAppleMaps)) {
      opcoes.add(_AbrirOpcao(nome: 'Apple Maps', icone: Icons.map_outlined, uri: urlAppleMaps));
    }
    if (urlNavegador != null && await canLaunchUrl(urlNavegador)) {
      opcoes.add(_AbrirOpcao(nome: 'Navegador', icone: Icons.open_in_browser, uri: urlNavegador));
    }

    if (opcoes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum app compatível encontrado.')),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Abrir com', style: TextStyle(fontWeight: FontWeight.w700))),
            ...opcoes.map((o) => ListTile(
              leading: Icon(o.icone),
              title: Text(o.nome),
              onTap: () async {
                Navigator.of(ctx).pop();

                // NEW: registra via escolhida (antes de abrir o app)
                final via = () {
                  switch (o.nome.toLowerCase()) {
                    case 'google maps':
                      return 'google_maps';
                    case 'waze':
                      return 'waze';
                    case 'apple maps':
                      return 'apple_maps';
                    case 'navegador':
                      return 'navegador';
                    default:
                      return 'desconhecido';
                  }
                }();
                logAcessoRota(upa: upa, origem: 'home', via: via); // fire-and-forget

                final ok = await launchUrl(o.uri, mode: LaunchMode.externalApplication);
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Falha ao abrir ${o.nome}.')),
                  );
                }
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // =========================
  // COMPARTILHAR ROTA
  // =========================
  Uri? _montarUrlParaCompartilhar(UpaRecord upa) {
    final alvo = resolverAlvo(upa);
    final plusRaw = obterPlusCode(upa.atributos);
    final plus = sanitizePlusCode(plusRaw);

    if (alvo != null) {
      final lat = alvo.lat.toString();
      final lon = alvo.lon.toString();
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    }
    if (plus != null && plus.trim().isNotEmpty) {
      final qp = Uri.encodeComponent(plus);
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=$qp');
    }
    return null;
  }

  Future<void> _compartilharRota(UpaRecord upa) async {
    final uri = _montarUrlParaCompartilhar(upa);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem Plus Code ou coordenadas para compartilhar.')),
      );
      return;
    }

    final titulo = nomeParaExibir(upa);
    final texto = '$titulo\n${uri.toString()}';
    try {
      // estatística opcional
      logAcessoRota(upa: upa, origem: 'home', via: 'compartilhar');
    } catch (_) {}
    await Share.share(texto, subject: 'Rota - $titulo');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.agriculture, color: Colors.white),
            SizedBox(width: 8),
            Text('Rotas Rurais', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),

      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: MyApp.kBlue),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'assets/logo_semit.png',
                      width: 60,
                      height: 60,
                    ),
                    const Spacer(),
                    const Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        'Menu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [

                    ListTile(
                      leading: const Icon(Icons.search),
                      title: const Text('Buscar Avançada'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const BuscaAvancadaPage()));
                      },
                    ),


                    ListTile(
                      leading: const Icon(Icons.bar_chart),
                      title: const Text('Estatísticas'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const EstatisticasPage()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance),
                      title: const Text('Serviços Públicos'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ServicosPublicosPage()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Sobre'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SobrePage()));
                      },
                    ),

                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Gerenciamento'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const UpaCrudPage()));
                      },
                    ),

                    ListTile(
                      leading: const Icon(Icons.accessibility),
                      title: const Text('Depurador'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const CorretorPage()));
                      },
                    ),


                  ],
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "Secretaria de\nInovação e Tecnologia",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/fundo.jpeg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.white.withOpacity(0.45))),
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0), child: const SizedBox.shrink())),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(blurRadius: 16, offset: Offset(0, 8), color: Color(0x331565C0)),
                      ],
                    ),
                    child: Material(
                      elevation: 14,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                      child: TextField(
                        controller: _buscaCtrl,
                        textInputAction: TextInputAction.search,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Digite o código...',
                          hintStyle: const TextStyle(fontSize: 17, color: Colors.black54),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _buscaCtrl.text.isEmpty
                              ? null
                              : IconButton(
                            onPressed: _limparBusca,
                            icon: const Icon(Icons.close),
                            tooltip: 'Limpar',
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0x551565C0), width: 1.2),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: MyApp.kBlue, width: 2.2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (valor) {
                          // se quiser contar Enter sempre, descomente:
                          // logBusca(termo: valor, origem: 'home').catchError((e) => debugPrint('logBusca falhou: $e'));
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: StreamBuilder<DatabaseEvent>(
                    stream: _ref.onValue,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Erro ao carregar dados do Firebase:\n${snap.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final val = snap.data?.snapshot.value;
                      final List<UpaRecord> lista = [];
                      if (val is Map) {
                        final root = val.cast<dynamic, dynamic>();
                        root.forEach((_, v) {
                          if (v is Map) {
                            final rec = _upaFromMap(v.cast<dynamic, dynamic>());
                            if (rec != null) lista.add(rec);
                          }
                        });
                      }

                      final termo = _buscaCtrl.text.trim().toLowerCase();
                      final resultado = _filtrar(lista, termo);

                      // ---- REGISTRO DE BUSCAS ----
                      if (termo.length >= 3 && resultado.isNotEmpty && !_termosLogados.contains(termo)) {
                        _termosLogados.add(termo);
                        final codigoEncontrado = resultado.length == 1
                            ? (resultado.first.codigoUpa ?? '').trim()
                            : null;

                        // não await para não travar UI
                        logBusca(
                          termo: termo,
                          origem: 'home',
                          codigoUpa: (codigoEncontrado?.isEmpty ?? true) ? null : codigoEncontrado,
                        ).catchError((e) => debugPrint('Falha ao registrar estatística: $e'));
                      }
                      // -----------------------------

                      if (resultado.isEmpty) {
                        return _EmptyState(carregou: snap.hasData, total: lista.length);
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: resultado.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final upa = resultado[i];
                          return _UpaCard(
                            upa: upa,
                            onAbrir: () => _abrirEscolherApp(upa),
                            onCompartilhar: () => _compartilharRota(upa), // <-- novo callback
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: Container(
        color: MyApp.kBlue,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Secretaria de Inovação e Tecnologia',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white)),
                SizedBox(height: 4),
                Text('© SEMIT 2025',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================
/// SUPORTE / MODELOS
/// =========================
class _EmptyState extends StatelessWidget {
  final bool carregou;
  final int total;
  const _EmptyState({required this.carregou, required this.total});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.search_off, size: 72, color: Colors.white70),
            SizedBox(height: 12),
            Text('Digite os 3 últimos dígitos no campo acima.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _UpaCard extends StatelessWidget {
  final UpaRecord upa;
  final VoidCallback onAbrir;
  final VoidCallback onCompartilhar; // NOVO
  const _UpaCard({required this.upa, required this.onAbrir, required this.onCompartilhar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = nomeParaExibir(upa);
    final display = buildDisplayAttributes(upa);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (upa.codigoUpa != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text('UPA: ${upa.codigoUpa}',
                        style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAbrir,
                icon: const Icon(Icons.location_on),
                label: const Text('Localização'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCompartilhar,
                icon: const Icon(Icons.share),
                label: const Text('Compartilhar rota'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Detalhes', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...display.map((kv) => kvTile(kv.$1, kv.$2)),
          ],
        ),
      ),
    );
  }
}

class UpaRecord {
  final String? codigoUpa;
  final String? nome;
  final LatLng? coord;
  final Map<String, String> atributos;
  UpaRecord({required this.codigoUpa, required this.nome, required this.coord, required this.atributos});
}

class LatLng {
  final double lat;
  final double lon;
  const LatLng(this.lat, this.lon);
}

class _AbrirOpcao {
  final String nome;
  final IconData icone;
  final Uri uri;
  _AbrirOpcao({required this.nome, required this.icone, required this.uri});
}

String nomeParaExibir(UpaRecord upa) {
  final n = (upa.nome ?? '').trim();
  if (n.isNotEmpty && n.toLowerCase() != 'sem nome') return n;

  final attrs = upa.atributos;
  final candidatos = ['nome upa', 'nome_upa', 'upa', 'nome', 'propriedade', 'fazenda'];
  for (final k in candidatos) {
    final match = attrs.entries.firstWhere(
          (e) => e.key.toLowerCase().trim() == k,
      orElse: () => const MapEntry('', ''),
    );
    if (match.key.isNotEmpty && match.value.trim().isNotEmpty) return match.value.trim();
  }

  if ((upa.codigoUpa ?? '').trim().isNotEmpty) return upa.codigoUpa!.trim();
  return 'UPA sem identificação';
}

LatLng? resolverAlvo(UpaRecord upa) {
  if (upa.coord != null) return upa.coord;
  final plusRaw = obterPlusCode(upa.atributos);
  final plus = sanitizePlusCode(plusRaw);
  return decodePlusAsLatLngIfGlobal(plus);
}

LatLng? decodePlusAsLatLngIfGlobal(String? plus) {
  if (plus == null) return null;
  final puro = plus.split(',').first.trim();
  final isGlobal = puro.contains('+') && puro.replaceAll('+', '').length >= 8;
  if (!isGlobal) return null;
  try {
    final area = olc.PlusCode(puro).decode();
    final center = area.center;
    return LatLng(center.latitude, center.longitude);
  } catch (_) {
    return null;
  }
}

String? obterPlusCode(Map<String, String> attrs) {
  const candidatos = [
    'global_code', 'plus_code', 'compound_code', 'plus code', 'pluscode',
    'plus-code', 'plus', 'pluscode upa',
  ];
  for (final k in candidatos) {
    final entry = attrs.entries.firstWhere(
          (e) => e.key.toLowerCase().trim() == k,
      orElse: () => const MapEntry('', ''),
    );
    if (entry.key.isNotEmpty && entry.value.trim().isNotEmpty) {
      return entry.value.trim();
    }
  }
  for (final e in attrs.entries) {
    final lk = e.key.toLowerCase().trim();
    if (lk.contains('global_code') || lk.contains('compound_code')) {
      final v = e.value.trim();
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

String? sanitizePlusCode(String? code) {
  if (code == null) return null;
  var c = code.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
  c = c.replaceAll(RegExp(r'\s+'), ' ');
  return c;
}

Widget kvTile(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}

List<(String, String)> buildDisplayAttributes(UpaRecord upa) {
  final attrs = upa.atributos;

  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');

  const labelMap = {
    'nomeupa': 'UPA',
    'upa': 'UPA',
    'nome': 'UPA',
    'municipio': 'Município',
    'cidade': 'Município',
    'tipoempreendimento': 'Emp.',
    'empreendimentotype': 'Emp.',
    'tipo': 'Tipo',
    'proprietario': 'Proprietário',
    'responsavel': 'Responsável',
    'globalcode': 'Plus Code',
    'pluscode': 'Plus Code',
    'compoundcode': 'Plus Code',
    'latitude': 'Latitude',
    'longitude': 'Longitude',
    'areahectares': 'Área (ha)',
  };

  bool ocultar(String k) {
    final n = norm(k);
    const ban = {
      'codigoupa','códigoupa','geometry','x','y','type','coordinates','cordinates',
      'globalid','objectid','latitude','longitude','globalcode','pluscode','compoundcode',
    };
    return ban.contains(n);
  }

  final List<(String, String)> out = [];
  for (final e in attrs.entries) {
    final k = e.key;
    final v = e.value.trim();
    if (v.isEmpty) continue;
    if (ocultar(k)) continue;

    final n = norm(k);
    final label = labelMap[n] ?? titleCase(k.replaceAll('_', ' '));
    out.add((label, v));
  }

  int rank(String label) {
    switch (label) {
      case 'UPA':
        return 0;
      case 'Emp.':
        return 1;
      case 'Município':
        return 2;
      case 'Tipo':
        return 3;
      case 'Proprietário':
        return 4;
      case 'Responsável':
        return 5;
      default:
        return 10;
    }
  }

  out.sort((a, b) {
    final r = rank(a.$1).compareTo(rank(b.$1));
    if (r != 0) return r;
    return a.$1.compareTo(b.$1);
  });

  return out;
}

String titleCase(String s) {
  final parts = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  return parts.map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase()).join(' ');
}

List<UpaRecord> _filtrar(List<UpaRecord> base, String termoRaw) {
  final termo = termoRaw.trim().toLowerCase();
  if (termo.isEmpty) return [];

  return base.where((e) {
    final codigo = (e.codigoUpa ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (codigo.isEmpty) return false;

    if (termo.length == 3) {
      final ultimos3 = codigo.length >= 3 ? codigo.substring(codigo.length - 3) : codigo;
      return ultimos3 == termo;
    }
    return codigo == termo || codigo.contains(termo);
  }).toList();
}

/// =========================
/// LOG DE BUSCAS (ESTATÍSTICAS)
/// =========================

String _hoje() => DateFormat('yyyy-MM-dd').format(DateTime.now());

// Incremento simplificado (sem transação), usando ServerValue.increment(1)
Future<void> _inc(String path) async {
  await FirebaseDatabase.instance.ref(path).set(ServerValue.increment(1));
}

Future<void> logBusca({
  required String termo,
  required String origem, // 'home' | 'busca_avancada'
  String? codigoUpa,
}) async {
  final t = termo.trim().toLowerCase();
  if (t.isEmpty) return;

  final dia = _hoje();

  try {
    await _inc('estatisticas/buscas/totais/$dia');
    await _inc('estatisticas/buscas/totalGeral');

    await _inc('estatisticas/buscas/origem/$origem/$dia');
    await _inc('estatisticas/buscas/origem/$origem/totalGeral');

    await _inc('estatisticas/buscas/porTermo/$t/$dia');
    await _inc('estatisticas/buscas/porTermo/$t/totalGeral');

    if (codigoUpa != null && codigoUpa.trim().isNotEmpty) {
      final c = codigoUpa.trim();
      await _inc('estatisticas/buscas/porCodigo/$c/$dia');
      await _inc('estatisticas/buscas/porCodigo/$c/totalGeral');
    }

    await FirebaseDatabase.instance.ref('estatisticas/buscas/ultimo').set({
      'termo': t,
      'origem': origem,
      'ts': ServerValue.timestamp,
    });
  } catch (e, s) {
    debugPrint('logBusca falhou: $e\n$s');
    rethrow;
  }
}
