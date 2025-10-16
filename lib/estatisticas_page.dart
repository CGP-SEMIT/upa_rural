// lib/estatisticas_page.dart (revisado)
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// Para usar MyApp.kBlue no AppBar e no rodapé
import 'main.dart' show MyApp;

class EstatisticasPage extends StatelessWidget {
  const EstatisticasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('upas');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estatísticas'),
        backgroundColor: MyApp.kBlue,
        foregroundColor: Colors.white,
      ),

      // ====== BACKGROUND igual ao padrão ======
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/fundo.jpeg', fit: BoxFit.cover),
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

          // ====== CONTEÚDO ======
          SafeArea(
            child: StreamBuilder<DatabaseEvent>(
              stream: ref.onValue,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Erro ao carregar estatísticas:\n${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final data = snap.data?.snapshot.value;
                final items = _normalizarLista(data);

                final total = items.length;

                int comCoord = 0;
                int comPlus = 0;
                final porMunicipio = <String, int>{};

                for (final m in items) {
                  final attrs = _achatar(m);

                  // Coordenadas: tente na raiz e em geometry
                  final lat = _toDouble(
                    attrs['latitude'] ?? attrs['geometry.latitude'],
                  );
                  final lon = _toDouble(
                    attrs['longitude'] ?? attrs['geometry.longitude'],
                  );
                  if (lat != null && lon != null) comCoord++;

                  // Plus Code: várias chaves possíveis
                  final plus = _primeiroValor(
                    attrs,
                    const [
                      'global_code',
                      'plus_code',
                      'compound_code',
                      'plus code',
                      'pluscode',
                      'plus-code',
                      'plus',
                      'pluscode upa',
                    ],
                  );
                  if ((plus ?? '').trim().isNotEmpty) comPlus++;

                  // Município: normalize chaves comuns
                  final municipio =
                  (_primeiroValor(attrs, const ['municipio', 'cidade']) ?? '')
                      .toString()
                      .trim();
                  if (municipio.isNotEmpty) {
                    porMunicipio.update(municipio, (v) => v + 1, ifAbsent: () => 1);
                  }
                }

                // Ordena municípios por contagem desc
                final muniOrdenado = porMunicipio.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _KpiCard(
                      title: 'Total de UPAs',
                      value: total.toString(),
                      icon: Icons.apartment,
                    ),
                    const SizedBox(height: 12),
                    _KpiGrid(values: [
                      ('Com coordenadas', comCoord.toString(), Icons.place),
                      ('Com Plus Code', comPlus.toString(), Icons.add_location_alt),
                    ]),
                    const SizedBox(height: 24),
                    const Text(
                      'Por município',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (muniOrdenado.isEmpty)
                      const Text('Sem dados de município.')
                    else
                      ...muniOrdenado.map(
                            (e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_city),
                          title: Text(e.key),
                          trailing: Text(
                            e.value.toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    const RotasMaisAcessadas(),
                  ],
                );
              },
            ),
          ),
        ],
      ),

      // ====== RODAPÉ igual ao padrão ======
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
}

/// === Helpers de normalização ===

List<Map<String, dynamic>> _normalizarLista(dynamic data) {
  final out = <Map<String, dynamic>>[];

  if (data is Map) {
    data.forEach((_, v) {
      if (v is Map) {
        out.add(v.map((k, vv) => MapEntry(k.toString(), vv)));
      } else if (v is List) {
        for (final it in v) {
          if (it is Map) {
            out.add(it.map((k, vv) => MapEntry(k.toString(), vv)));
          }
        }
      }
    });
  } else if (data is List) {
    for (final it in data) {
      if (it is Map) {
        out.add(it.map((k, vv) => MapEntry(k.toString(), vv)));
      }
    }
  }
  return out;
}

Map<String, dynamic> _achatar(Map<String, dynamic> raw) {
  final flat = <String, dynamic>{};

  void addPrefixed(String prefix, Map m) {
    m.forEach((k, v) {
      final key = '$prefix.${k.toString()}';
      flat[key] = v;
      if (v is Map) addPrefixed(key, v);
    });
  }

  raw.forEach((k, v) {
    flat[k] = v;
    if (v is Map) addPrefixed(k.toString(), v);
  });

  // também versões lowercase/sem espaços para busca fácil
  final copy = Map<String, dynamic>.from(flat);
  copy.forEach((k, v) {
    flat[k.toLowerCase().trim()] = v;
    flat[k.replaceAll('_', ' ').toLowerCase().trim()] = v;
  });

  return flat;
}

double? _toDouble(dynamic x) {
  if (x == null) return null;
  if (x is num) return x.toDouble();
  return double.tryParse(x.toString());
}

String? _primeiroValor(Map<String, dynamic> attrs, List<String> chaves) {
  for (final k in chaves) {
    final v = attrs[k] ??
        attrs[k.toLowerCase()] ??
        attrs[k.replaceAll('_', ' ').toLowerCase()];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  // fallback: procura por chaves que contém o termo
  for (final e in attrs.entries) {
    final lk = e.key.toLowerCase();
    if (chaves.any((c) => lk.contains(c.toLowerCase()))) {
      final v = e.value?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  return null;
}

/// === UI ===

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _KpiCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final List<(String, String, IconData)> values;
  const _KpiGrid({required this.values});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: values
          .map(
            (e) => Expanded(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                children: [
                  Icon(e.$3, color: cs.primary),
                  const SizedBox(height: 8),
                  Text(e.$1, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(
                    e.$2,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
          .toList(),
    );
  }
}

// Widget para exibir as rotas mais acessadas
class RotasMaisAcessadas extends StatelessWidget {
  const RotasMaisAcessadas({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('estatisticas/rotas/porRota').onValue,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const Text('Erro ao carregar as rotas mais acessadas.');
        }
        if (!snap.hasData || snap.data?.snapshot.value == null) {
          return const Text('Nenhuma rota acessada ainda.');
        }

        final data = snap.data?.snapshot.value as Map? ?? {};
        final rotas = data.entries.map((e) {
          final key = e.key as String;
          final value = e.value as Map? ?? {};
          final total = value['totalGeral'] as int? ?? 0;
          return MapEntry(key, total);
        }).toList();

        rotas.sort((a, b) => b.value.compareTo(a.value));

        final topRotas = rotas.take(10).toList(); // Exibe as 10 mais acessadas

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top 10 Rotas Mais Acessadas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (topRotas.isEmpty)
              const Text('Sem dados de rotas.')
            else
              ...topRotas.map(
                    (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route),
                  title: Text(e.key), // Exibe a rotaKey
                  trailing: Text(
                    e.value.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
