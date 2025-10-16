// lib/busca_avancada_page.dart (revisado)
// Tela de busca por Nome e Município, com o MESMO visual da Home e
// **registrando rotas mais acessadas** somente após abrir o app com sucesso,
// evitando duplicidade por sessão. Agora com botão "Compartilhar rota".

import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart'; // <-- NOVO

// Reaproveita modelos/helpers PÚBLICOS da main.dart (sem underline!)
import 'main.dart'
    show
    UpaRecord,
    LatLng,
    MyApp,
    nomeParaExibir,
    buildDisplayAttributes,
    kvTile,
    resolverAlvo,
    obterPlusCode,
    sanitizePlusCode,
    decodePlusAsLatLngIfGlobal;

/// =========================
/// BUSCA (NOME + MUNICÍPIO)
/// =========================
class BuscaAvancadaPage extends StatefulWidget {
  const BuscaAvancadaPage({super.key});
  @override
  State<BuscaAvancadaPage> createState() => _BuscaAvancadaPageState();
}

class _BuscaAvancadaPageState extends State<BuscaAvancadaPage> {
  final DatabaseReference _ref = FirebaseDatabase.instance.ref('upas');
  final _nomeCtrl = TextEditingController();
  final _munCtrl = TextEditingController();

  // Evita contar a mesma UPA várias vezes na MESMA sessão (tela de busca)
  final Set<String> _rotasLogadas = <String>{};

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _munCtrl.dispose();
    super.dispose();
  }

  void _limparCampos() {
    _nomeCtrl.clear();
    _munCtrl.clear();
    setState(() {});
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
            Text(
              'Busca Avançada',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: MyApp.kBlue,
        foregroundColor: Colors.white,
      ),

      // BACKGROUND idêntico ao da Home
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/fundo.jpeg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.45)),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
              child: const SizedBox.shrink(),
            ),
          ),

          // CONTEÚDO
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ====== CAMPOS ======
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      _campoElevado(
                        context: context,
                        hint: 'Nome da UPA / Propriedade',
                        controller: _nomeCtrl,
                        icon: Icons.home_outlined,
                      ),
                      const SizedBox(height: 10),
                      _campoElevado(
                        context: context,
                        hint: 'Município',
                        controller: _munCtrl,
                        icon: Icons.location_city,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _limparCampos,
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpar'),
                        ),
                      ),
                    ],
                  ),
                ),

                // ====== RESULTADOS ======
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

                      final raw = snap.data?.snapshot.value;
                      final List<UpaRecord> lista = [];
                      if (raw is Map) {
                        final root = raw.cast<dynamic, dynamic>();
                        root.forEach((_, v) {
                          if (v is Map) {
                            final rec = _upaFromMapExt(v.cast<dynamic, dynamic>());
                            if (rec != null) lista.add(rec);
                          }
                        });
                      }






                      final res = _filtrarNomeMunicipio(
                        base: lista,
                        nome: _nomeCtrl.text,
                        municipio: _munCtrl.text,
                      );

                      if (res.isEmpty) return const _EmptyAdvancedNM();

// 🔽 Ordenação aqui, sem mexer no filtro
                      int last3Codigo(UpaRecord e) {
                        final raw = (e.codigoUpa ?? '').replaceAll(RegExp(r'\D'), '');
                        if (raw.isEmpty) return 1 << 30; // sem código: joga para o fim
                        final tail = raw.length <= 3 ? raw : raw.substring(raw.length - 3);
                        return int.tryParse(tail) ?? (1 << 30);
                      }

                      res.sort((a, b) {
                        final la = last3Codigo(a);
                        final lb = last3Codigo(b);
                        if (la != lb) return la.compareTo(lb);
                        // empate -> nome para estabilidade
                        return nomeParaExibir(a).toLowerCase().compareTo(nomeParaExibir(b).toLowerCase());
                      });

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: res.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final upa = res[i];
                          return _UpaCardAvancado(
                            upa: upa,
                            onAbrir: () => _abrirEscolherAppLocal(context, upa),
                            onCompartilhar: () => _compartilharRotaLocal(context, upa),
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

      // RODAPÉ igual ao da Home
      bottomNavigationBar: Container(
        color: MyApp.kBlue,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Secretaria de Inovação e Tecnologia',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  '© SEMIT 2025',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== Campo elevado no mesmo estilo da Home =====
  Widget _campoElevado({
    required BuildContext context,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            spreadRadius: 0,
            offset: Offset(0, 8),
            color: Color(0x331565C0), // glow azul claro
          ),
        ],
      ),
      child: Material(
        elevation: 14,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        child: TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 17, color: Colors.black54),
            prefixIcon: Icon(icon),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
              onPressed: () {
                controller.clear();
                setState(() {});
              },
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
        ),
      ),
    );
  }

  /// =========================
  /// ABRIR EM APP DE MAPA (local) + REGISTRO DE ACESSOS
  /// =========================
  Future<void> _abrirEscolherAppLocal(BuildContext context, UpaRecord upa) async {
    final alvo = resolverAlvo(upa);
    final plusRaw = obterPlusCode(upa.atributos);
    final plus = sanitizePlusCode(plusRaw);

    if (alvo == null && plus == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem Plus Code ou coordenadas disponíveis.')),
      );
      return;
    }

    final label = Uri.encodeComponent(nomeParaExibir(upa));
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
      urlNavegador = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    } else {
      final qp = Uri.encodeComponent(plus!);
      urlGoogleMapsApp = Uri.parse('https://www.google.com/maps/search/?api=1&query=$qp');
      urlNavegador = urlGoogleMapsApp;
      urlAppleMaps = Uri.parse('http://maps.apple.com/?q=$qp');
      urlWazeApp = null; // sem lat/lon, não usar Waze
    }

    final List<_AbrirOpcaoLocal> opcoes = [];

    if (urlGoogleMapsApp != null && await canLaunchUrl(urlGoogleMapsApp)) {
      opcoes.add(_AbrirOpcaoLocal('Google Maps', Icons.map, urlGoogleMapsApp));
    }
    if (urlWazeApp != null && await canLaunchUrl(urlWazeApp)) {
      opcoes.add(_AbrirOpcaoLocal('Waze', Icons.directions_car, urlWazeApp));
    }
    if (Platform.isIOS && urlAppleMaps != null && await canLaunchUrl(urlAppleMaps)) {
      opcoes.add(_AbrirOpcaoLocal('Apple Maps', Icons.map_outlined, urlAppleMaps));
    }
    if (urlNavegador != null && await canLaunchUrl(urlNavegador)) {
      opcoes.add(_AbrirOpcaoLocal('Navegador', Icons.open_in_browser, urlNavegador));
    }

    if (opcoes.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum app compatível encontrado.')),
      );
      return;
    }

    if (!context.mounted) return;
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
            const ListTile(
              title: Text('Abrir com', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ...opcoes.map((o) => ListTile(
              leading: Icon(o.icone),
              title: Text(o.nome),
              onTap: () async {
                Navigator.of(ctx).pop();

                // Detecta a via escolhida
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

                final ok = await launchUrl(o.uri, mode: LaunchMode.externalApplication);

                if (ok) {
                  // ✅ Conta somente após abrir com sucesso
                  final key = _rotaKeyLocal(upa);
                  if (!_rotasLogadas.contains(key)) {
                    _rotasLogadas.add(key);
                    // primeira vez na sessão: contabiliza tudo
                    await _logAcessoRotaAvancada(upa: upa, origem: 'busca_avancada', via: via);
                  } else {
                    // já contamos esta UPA na sessão -> atualiza apenas os cortes de via
                    await _logViaOnly(key: key, via: via);
                  }
                } else if (context.mounted) {
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
  // COMPARTILHAR ROTA (local) com deduplicação por sessão
  // =========================
  Uri? _montarUrlParaCompartilharLocal(UpaRecord upa) {
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

  Future<void> _compartilharRotaLocal(BuildContext context, UpaRecord upa) async {
    final uri = _montarUrlParaCompartilharLocal(upa);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem Plus Code ou coordenadas para compartilhar.')),
      );
      return;
    }

    final titulo = nomeParaExibir(upa);
    final texto = '$titulo\n${uri.toString()}';

    // Estatística: usamos mesmo critério de deduplicação da sessão.
    final key = _rotaKeyLocal(upa);
    if (!_rotasLogadas.contains(key)) {
      _rotasLogadas.add(key);
      await _logAcessoRotaAvancada(upa: upa, origem: 'busca_avancada', via: 'compartilhar');
    } else {
      await _logViaOnly(key: key, via: 'compartilhar');
    }

    await Share.share(texto, subject: 'Rota - $titulo');
  }

  /// =========================
  /// Helpers de registro (versões locais desta tela)
  /// =========================

  String _municipioDeLocal(Map<String, String> attrs) {
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

  String _rotaKeyLocal(UpaRecord upa) {
    final c = (upa.codigoUpa ?? '').trim();
    if (c.isNotEmpty) return 'codigo:$c';

    final plus = (obterPlusCode(upa.atributos) ?? '').trim();
    if (plus.isNotEmpty) return 'plus:$plus';

    final n = (upa.nome ?? '').trim();
    if (n.isNotEmpty) return 'nome:$n';

    return 'hash:${upa.atributos.hashCode}';
  }

  Future<void> _incRotaLocal(String path) async {
    await FirebaseDatabase.instance.ref(path).set(ServerValue.increment(1));
  }

  String _hoje() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _logAcessoRotaAvancada({
    required UpaRecord upa,
    required String origem, // 'busca_avancada'
    String? via,
  }) async {
    final key = _rotaKeyLocal(upa);
    final dia = _hoje();
    final muni = _municipioDeLocal(upa.atributos);

    try {
      // totais globais
      await _incRotaLocal('estatisticas/rotas/totais/$dia');
      await _incRotaLocal('estatisticas/rotas/totalGeral');

      // por rota
      await _incRotaLocal('estatisticas/rotas/porRota/$key/$dia');
      await _incRotaLocal('estatisticas/rotas/porRota/$key/totalGeral');

      // por município
      if (muni.isNotEmpty) {
        await _incRotaLocal('estatisticas/rotas/porMunicipio/$muni/$dia');
        await _incRotaLocal('estatisticas/rotas/porMunicipio/$muni/totalGeral');
      }

      // origem e via
      await _incRotaLocal('estatisticas/rotas/origem/$origem/$dia');
      await _incRotaLocal('estatisticas/rotas/origem/$origem/totalGeral');

      if ((via ?? '').isNotEmpty) {
        await _incRotaLocal('estatisticas/rotas/via/$via/$dia');
        await _incRotaLocal('estatisticas/rotas/via/$via/totalGeral');
        await _incRotaLocal('estatisticas/rotas/porRotaVia/$key/$via/$dia');
        await _incRotaLocal('estatisticas/rotas/porRotaVia/$key/$via/totalGeral');
      }

      // último acesso
      await FirebaseDatabase.instance.ref('estatisticas/rotas/ultimo').set({
        'rotaKey': key,
        'codigo': upa.codigoUpa,
        'nome': upa.nome,
        'municipio': muni,
        'origem': origem,
        'via': via,
        'ts': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('logAcessoRotaAvancada falhou: $e');
    }
  }

  Future<void> _logViaOnly({required String key, required String via}) async {
    final dia = _hoje();
    try {
      await _incRotaLocal('estatisticas/rotas/via/$via/$dia');
      await _incRotaLocal('estatisticas/rotas/via/$via/totalGeral');
      await _incRotaLocal('estatisticas/rotas/porRotaVia/$key/$via/$dia');
      await _incRotaLocal('estatisticas/rotas/porRotaVia/$key/$via/totalGeral');
    } catch (e) {
      debugPrint('logViaOnly falhou: $e');
    }
  }
}

/// =========================
/// EMPTY STATE
/// =========================
class _EmptyAdvancedNM extends StatelessWidget {
  const _EmptyAdvancedNM();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.travel_explore, size: 72, color: Colors.white70),
            SizedBox(height: 12),
            Text(
              'Busque por Nome da propriedade e/ou Município.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================
/// CARD (AVANÇADO)
/// =========================
class _UpaCardAvancado extends StatelessWidget {
  final UpaRecord upa;
  final VoidCallback onAbrir;
  final VoidCallback onCompartilhar; // <-- NOVO
  const _UpaCardAvancado({
    super.key,
    required this.upa,
    required this.onAbrir,
    required this.onCompartilhar,
  });

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
                  child: Text(
                    titulo,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (upa.codigoUpa != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'UPA: ${upa.codigoUpa}',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAbrir,
                icon: const Icon(Icons.navigation),
                label: const Text('Navegar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8), // espaçamento entre botões
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

/// =========================
/// CONVERSOR (standalone) PARA ESTA TELA
/// =========================
UpaRecord? _upaFromMapExt(Map<dynamic, dynamic> raw) {
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
/// FILTRO CLIENT-SIDE (Nome + Município)
/// =========================
List<UpaRecord> _filtrarNomeMunicipio({
  required List<UpaRecord> base,
  required String nome,
  required String municipio,
}) {
  String norm(String s) => s.trim().toLowerCase();

  final n = norm(nome);
  final m = norm(municipio);

  bool bate(String valor, String termo) {
    if (termo.isEmpty) return true;
    final v = norm(valor);
    return v.contains(termo);
  }

  return base
      .where((e) {
    final attrs = e.atributos.map((k, v) => MapEntry(k.toLowerCase().trim(), v));

    // Nome/UPA/Propriedade
    final nomeKeys = ['nome', 'nome_upa', 'nome upa', 'upa', 'propriedade', 'fazenda'];
    final txtNome = [
      e.nome ?? '',
      ...nomeKeys.map((k) => attrs[k] ?? ''),
      nomeParaExibir(e),
    ].join(' | ');

    // Município
    final munKeys = ['municipio', 'município', 'cidade', 'municipio_upa', 'municipio upa'];
    final txtMun = munKeys.map((k) => attrs[k] ?? '').join(' | ');

    final okNome = bate(txtNome, n);
    final okMun = bate(txtMun, m);

    return okNome && okMun;
  })
      .toList()
    ..sort((a, b) => nomeParaExibir(a).toLowerCase().compareTo(nomeParaExibir(b).toLowerCase()));
}

class _AbrirOpcaoLocal {
  final String nome;
  final IconData icone;
  final Uri uri;
  _AbrirOpcaoLocal(this.nome, this.icone, this.uri);
}
