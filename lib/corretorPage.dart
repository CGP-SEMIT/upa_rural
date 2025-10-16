// lib/corretor_page.dart
// Tela "Corretor": Duplicados por codigo_upa + Registros sem propriedade (com MOTIVO)
// Exporta/Imprime o resultado visível (com coluna "Motivo" quando aplicável).
//
// Ajuste: manter duplicados como está; no modo "semPropriedade" exibir também as
// lacunas (pelos 3 últimos dígitos do codigo_upa) e incluí-las no PDF.

import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';

// Reaproveita utilidades públicas da main.dart (sem underscore!)
import 'main.dart'
    show
    UpaRecord,
    MyApp,
    nomeParaExibir,
    obterPlusCode,
    sanitizePlusCode,
    decodePlusAsLatLngIfGlobal,
    LatLng;

/// ============ MODELO ============
enum _FiltroModo { duplicados, semPropriedade }

class _AvaliacaoProp {
  final bool ok;
  final String motivo; // quando ok=false, explica o problema
  const _AvaliacaoProp(this.ok, this.motivo);
}

class _RegComMotivo {
  final UpaRecord rec;
  final String motivo;
  const _RegComMotivo(this.rec, this.motivo);
}

class _ExportBundle {
  final String titulo;
  final _FiltroModo modo;
  final Map<String, List<UpaRecord>> grupos;
  // quando modo == semPropriedade, traz motivos por linha
  final Map<String, List<String>>? motivos;
  // NOVO: lacunas quando modo == semPropriedade
  final List<String>? lacunas;
  _ExportBundle({
    required this.titulo,
    required this.modo,
    required this.grupos,
    this.motivos,
    this.lacunas,
  });
}

/// ============ TELA ============
class CorretorPage extends StatefulWidget {
  const CorretorPage({super.key});
  @override
  State<CorretorPage> createState() => _CorretorPageState();
}

class _CorretorPageState extends State<CorretorPage> {
  final DatabaseReference _ref = FirebaseDatabase.instance.ref('upas');
  final ValueNotifier<_FiltroModo> _modo = ValueNotifier(_FiltroModo.duplicados);

  _ExportBundle? _lastExport;

  @override
  void dispose() {
    _modo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.rule_folder, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Corretor ',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              ),
            )
          ],
        ),
        backgroundColor: MyApp.kBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Salvar em PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _onSavePdf,
          ),
          IconButton(
            tooltip: 'Imprimir',
            icon: const Icon(Icons.print),
            onPressed: _onPrintPdf,
          ),
          const SizedBox(width: 4),
        ],
      ),

      // BACKGROUND padrão
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/fundo.jpeg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.white.withOpacity(0.45))),
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

                // Filtros
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ValueListenableBuilder<_FiltroModo>(
                    valueListenable: _modo,
                    builder: (context, modo, _) {
                      return SegmentedButton<_FiltroModo>(
                        segments: const [
                          ButtonSegment(
                            value: _FiltroModo.duplicados,
                            label: Text('Duplicados'),
                            icon: Icon(Icons.copy_all),
                          ),
                          ButtonSegment(
                            value: _FiltroModo.semPropriedade,
                            label: Text('Registros sem propriedade'),
                            icon: Icon(Icons.info_outline),
                          ),
                        ],
                        selected: {modo},
                        onSelectionChanged: (s) => _modo.value = s.first,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),

                // Resultados
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
                      final List<UpaRecord> base = [];
                      if (raw is Map) {
                        final root = raw.cast<dynamic, dynamic>();
                        root.forEach((_, v) {
                          if (v is Map) {
                            final rec = _upaFromMapExt(v.cast<dynamic, dynamic>());
                            final codigoOk = (rec?.codigoUpa ?? '').trim().isNotEmpty;
                            if (rec != null && codigoOk) base.add(rec);
                          }
                        });
                      }

                      if (base.isEmpty) {
                        _lastExport = null;
                        return const _ZeroStateInfo(
                          icon: Icons.inbox_outlined,
                          text: 'Sem registros para analisar.',
                        );
                      }

                      final grupos = _agruparPorCodigo(base);

                      return ValueListenableBuilder<_FiltroModo>(
                        valueListenable: _modo,
                        builder: (context, modo, _) {
                          if (modo == _FiltroModo.duplicados) {
                            // ========== Duplicados (MANTIDO) ==========
                            final dups = grupos.entries
                                .where((e) => e.value.length > 1)
                                .toList()
                              ..sort((a, b) => b.value.length.compareTo(a.value.length));

                            _lastExport = _ExportBundle(
                              titulo: 'Duplicados por codigo_upa',
                              modo: modo,
                              grupos: {for (final e in dups) e.key: e.value},
                            );

                            if (dups.isEmpty) {
                              return const _ZeroStateInfo(
                                icon: Icons.verified_outlined,
                                text: 'Nenhum codigo_upa duplicado encontrado.',
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: dups.length,
                              itemBuilder: (_, i) {
                                final codigo = dups[i].key;
                                final itens = dups[i].value;
                                return _GrupoCodigoCard(
                                  codigoUpa: codigo,
                                  registros: itens,
                                  badge: '${itens.length} registros',
                                );
                              },
                            );
                          }

                          // ========== Registros sem propriedade (MANTIDO) + LACUNAS (NOVO) ==========
                          final faltantes = grupos.entries
                              .map((e) {
                            final lista = <_RegComMotivo>[];
                            for (final r in e.value) {
                              final av = _avaliarPropriedade(r);
                              if (!av.ok) lista.add(_RegComMotivo(r, av.motivo));
                            }
                            return MapEntry(e.key, lista);
                          })
                              .where((e) => e.value.isNotEmpty)
                              .toList()
                            ..sort((a, b) => b.value.length.compareTo(a.value.length));

                          // NOVO: calcular lacunas pelos 3 últimos dígitos do codigo_upa
                          final lacunas = _calcularLacunasUltimos3(base);

                          _lastExport = _ExportBundle(
                            titulo: 'Registros sem informação de propriedade',
                            modo: modo,
                            grupos: {
                              for (final e in faltantes) e.key: e.value.map((x) => x.rec).toList()
                            },
                            motivos: {
                              for (final e in faltantes) e.key: e.value.map((x) => x.motivo).toList()
                            },
                            lacunas: lacunas,
                          );

                          if (faltantes.isEmpty && lacunas.isEmpty) {
                            return const _ZeroStateInfo(
                              icon: Icons.fact_check_outlined,
                              text: 'Não há registros faltando informação de propriedade nem lacunas.',
                            );
                          }

                          // UI: primeiro painel de Lacunas, depois lista de “sem propriedade”
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: (lacunas.isNotEmpty ? 1 : 0) + faltantes.length,
                            itemBuilder: (_, i) {
                              // bloco 0 -> painel de lacunas
                              if (lacunas.isNotEmpty && i == 0) {
                                return _PainelLacunas(lacunas: lacunas);
                              }

                              final idx = lacunas.isNotEmpty ? i - 1 : i;
                              final codigo = faltantes[idx].key;
                              final itens = faltantes[idx].value; // _RegComMotivo
                              return _GrupoCodigoCard(
                                codigoUpa: codigo,
                                registros: itens.map((x) => x.rec).toList(),
                                motivos: itens.map((x) => x.motivo).toList(),
                                destaque: true,
                                badge: '${itens.length} sem propriedade',
                              );
                            },
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

      // Rodapé
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
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white)),
                SizedBox(height: 4),
                Text('© SEMIT 2025',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========= Exportação / Impressão =========

  Future<void> _onSavePdf() async {
    if (_lastExport == null || _lastExport!.grupos.isEmpty) {
      // mesmo que só existam lacunas, ainda vale exportar
      if (_lastExport?.lacunas?.isNotEmpty == true) {
        final bytes = await _buildPdf(_lastExport!);
        final nome = _pdfFilename(_lastExport!);
        await Printing.sharePdf(bytes: bytes, filename: nome);
        return;
      }
      _snack('Nada para exportar.');
      return;
    }
    final bytes = await _buildPdf(_lastExport!);
    final nome = _pdfFilename(_lastExport!);
    await Printing.sharePdf(bytes: bytes, filename: nome);
  }

  Future<void> _onPrintPdf() async {
    if (_lastExport == null || _lastExport!.grupos.isEmpty) {
      // imprimir apenas lacunas, se houver
      if (_lastExport?.lacunas?.isNotEmpty == true) {
        await Printing.layoutPdf(onLayout: (_) => _buildPdf(_lastExport!));
        return;
      }
      _snack('Nada para imprimir.');
      return;
    }
    await Printing.layoutPdf(onLayout: (_) => _buildPdf(_lastExport!));
  }

  Future<Uint8List> _buildPdf(_ExportBundle data) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dataFmt =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final titulo = 'Corretor • ${data.titulo} • $dataFmt';

    final incluirMotivo = data.modo == _FiltroModo.semPropriedade && data.motivos != null;

    doc.addPage(
      pw.MultiPage(
        maxPages: 200,
        build: (ctx) {
          final widgets = <pw.Widget>[
            pw.Header(level: 0, child: pw.Text(titulo, style: pw.TextStyle(fontSize: 18))),
          ];

          // NOVO: seção de lacunas (apenas no modo semPropriedade e quando houver)
          if (data.modo == _FiltroModo.semPropriedade &&
              (data.lacunas?.isNotEmpty ?? false)) {
            widgets.add(pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: pdf.PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(width: 1, color: pdf.PdfColors.grey500),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Lacunas (001 até o maior sufixo encontrado):',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.SizedBox(height: 4),
                  pw.Text(data.lacunas!.join(', '), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ));
            widgets.add(pw.SizedBox(height: 10));
          }

          // Tabelas por grupo (duplicados ou sem propriedade)
          final chaves = data.grupos.keys.toList()..sort();
          for (final codigo in chaves) {
            final regs = data.grupos[codigo]!;
            final motivos = incluirMotivo ? (data.motivos![codigo] ?? const []) : const <String>[];

            widgets.add(pw.SizedBox(height: 10));
            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('codigo_upa: $codigo',
                            style: pw.TextStyle(
                                fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${regs.length} registro(s)',
                            style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    _tabelaRegistros(regs, incluirMotivo ? motivos : null),
                  ],
                ),
              ),
            );
          }
          return widgets;
        },
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Gerado por Corretor • pág. ${ctx.pageNumber}/${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9)),
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _tabelaRegistros(List<UpaRecord> regs, [List<String>? motivos]) {
    final temMotivo = motivos != null;
    final cols = {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(2),
      2: const pw.FlexColumnWidth(2),
      3: const pw.FlexColumnWidth(1.4),
      4: const pw.FlexColumnWidth(1.4),
      if (temMotivo) 5: const pw.FlexColumnWidth(3),
    };

    final header = [
      _cellH('Nome / Propriedade'),
      _cellH('Município'),
      _cellH('Plus Code'),
      _cellH('Lat'),
      _cellH('Lon'),
      if (temMotivo) _cellH('Motivo'),
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
        children: header,
      ),
      ...List.generate(regs.length, (i) {
        final e = regs[i];
        final attrs = _attrsLower(e);
        final nome = (nomeParaExibir(e)).trim();
        final muni = _pick(attrs, const ['municipio', 'município', 'cidade']);
        final plus = (sanitizePlusCode(obterPlusCode(e.atributos) ?? '') ?? '').trim();
        final lat = e.coord?.lat?.toStringAsFixed(6) ?? '';
        final lon = e.coord?.lon?.toStringAsFixed(6) ?? '';
        final linha = <pw.Widget>[
          _cell(nome.isEmpty ? '(sem nome)' : nome),
          _cell(muni.isEmpty ? '—' : muni),
          _cell(plus.isEmpty ? '—' : plus),
          _cell(lat.isEmpty ? '—' : lat),
          _cell(lon.isEmpty ? '—' : lon),
        ];
        if (temMotivo) linha.add(_cell(motivos![i]));
        return pw.TableRow(children: linha);
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.symmetric(inside: const pw.BorderSide(width: 0.2)),
      columnWidths: cols,
      children: rows,
    );
  }

  pw.Widget _cellH(String t) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(t, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
  );
  pw.Widget _cell(String t) =>
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(t, style: const pw.TextStyle(fontSize: 10)));

  String _pdfFilename(_ExportBundle data) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final base = data.modo == _FiltroModo.duplicados ? 'duplicados' : 'sem_propriedade';
    return 'corretor_${base}_$y$m$d.pdf';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ========= Helpers de dados =========

  static Map<String, List<UpaRecord>> _agruparPorCodigo(List<UpaRecord> base) {
    final out = <String, List<UpaRecord>>{};
    for (final e in base) {
      final c = (e.codigoUpa ?? '').trim();
      if (c.isEmpty) continue;
      out.putIfAbsent(c, () => []).add(e);
    }
    return out;
  }

  // ====== Validação de propriedade (com MOTIVO) ======

  // fragmentos que indicam campos de nome de propriedade/UPA (match por contains, já em lower)
  static const List<String> _propKeyFragments = [
    'propriedade',
    'nome_propriedade',
    'nome da propriedade',
    'fazenda',
    'nome_fazenda',
    'nome da fazenda',
    'nome_upa',
    'nome upa',
    'upa',
    'estabelecimento',
    'unidade',
    'imovel',
    'imóvel',
    'denominacao',
    'denominação',
    'sitio',
    'sítio',
    'chacara',
    'chácara',
    'gleba',
    'colonia',
    'colônia',
    'sede',
    'lote',
    'nome do imóvel',
    'nome do imovel',
  ];

  static String _cleanVal(String s) {
    // remove zero-width, normaliza, tira aspas/lixo nas pontas, colapsa espaços
    var v = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    v = v.trim().toLowerCase();
    v = v.replaceAll(RegExp(r'''^[\s"'`~|]+|[\s"'`~|]+$'''), '');
    v = v.replaceAll(RegExp(r'\s+'), ' ');
    return v;
  }

  static bool _isPlaceholder(String v) {
    final x = _cleanVal(v);
    const invalid = {
      '',
      '-',
      '—',
      'n/a',
      'na',
      'null',
      'undefined',
      '0',
      'sn',
      's/n',
      'sem nome',
      'sem',
      'vazio',
      '(sem nome)',
      'nao informado',
      'não informado',
      'nao possui',
      'não possui',
      'desconhecido',
      'sem informacao',
      'sem informação',
      'indefinido',
    };
    if (invalid.contains(x)) return true;
    if (RegExp(r'^[\W\d_]+$').hasMatch(x)) return true; // só número/pontuação
    if (x.length < 2) return true;
    return false;
  }

  // Avalia se o registro tem propriedade válida e explica o motivo quando NÃO tem.
  static _AvaliacaoProp _avaliarPropriedade(UpaRecord e) {
    final attrs = _attrsLower(e);

    String? keyHit;
    String? valHit;
    for (final entry in attrs.entries) {
      final key = entry.key; // já vem lower/trim
      // procura por qualquer variação relevante no NOME DA CHAVE
      if (_propKeyFragments.any((frag) => key.contains(frag))) {
        final val = _cleanVal(entry.value);
        if (val.isNotEmpty) {
          keyHit = key;
          valHit = val;
          break; // primeira ocorrência relevante
        }
      }
    }

    if (valHit == null || valHit.isEmpty) {
      return const _AvaliacaoProp(false, 'Nenhum campo de propriedade/UPA encontrado');
    }
    if (_isPlaceholder(valHit)) {
      return _AvaliacaoProp(false, 'Valor inválido em "$keyHit": "$valHit"');
    }
    return const _AvaliacaoProp(true, '');
  }

  static Map<String, String> _attrsLower(UpaRecord e) {
    final out = <String, String>{};
    e.atributos.forEach((k, v) {
      out[(k.toLowerCase().trim())] = (v ?? '').toString().trim();
    });
    return out;
  }

  static String _pick(Map<String, String> attrs, List<String> keys) =>
      keys.map((k) => attrs[k] ?? '').firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');

  // Conversor standalone (baseado no seu _upaFromMapExt)
  static UpaRecord? _upaFromMapExt(Map<dynamic, dynamic> raw) {
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

    final nome = (root['nome_upa'] ?? geom['nome_upa'] ?? root['nome'] ?? geom['nome'])?.toString();

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

  // ========= LACUNAS (NOVO) =========

  // Retorna os 3 últimos dígitos numéricos do codigo_upa; se não houver, retorna null
  static int? _last3FromCodigo(String codigoUpa) {
    final onlyDigits = codigoUpa.replaceAll(RegExp(r'\D'), '');
    if (onlyDigits.isEmpty) return null;
    final tail = onlyDigits.length <= 3 ? onlyDigits : onlyDigits.substring(onlyDigits.length - 3);
    return int.tryParse(tail);
  }

  // Calcula lacunas entre 001 e o maior sufixo presente na base
  static List<String> _calcularLacunasUltimos3(List<UpaRecord> base) {
    final presentes = <int>{};
    for (final e in base) {
      final c = (e.codigoUpa ?? '').trim();
      if (c.isEmpty) continue;
      final v = _last3FromCodigo(c);
      if (v != null) presentes.add(v);
    }
    if (presentes.isEmpty) return const [];
    final max = presentes.reduce((a, b) => a > b ? a : b);
    final lacunas = <String>[];
    for (int i = 1; i <= max; i++) {
      if (!presentes.contains(i)) {
        lacunas.add(i.toString().padLeft(3, '0'));
      }
    }
    return lacunas;
  }
}

/// ============ UI ============

class _GrupoCodigoCard extends StatelessWidget {
  final String codigoUpa;
  final List<UpaRecord> registros;
  final bool destaque;
  final String? badge;
  final List<String>? motivos; // quando semPropriedade, motivos por linha

  const _GrupoCodigoCard({
    super.key,
    required this.codigoUpa,
    required this.registros,
    this.destaque = false,
    this.badge,
    this.motivos,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: destaque ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.perm_identity, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'codigo_upa: $codigoUpa',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: destaque ? cs.errorContainer : cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: destaque ? cs.onErrorContainer : cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < registros.length; i++)
              _LinhaRegistro(registros[i], motivo: motivos?.elementAt(i)),
          ],
        ),
      ),
    );
  }
}

class _LinhaRegistro extends StatelessWidget {
  final UpaRecord e;
  final String? motivo;
  const _LinhaRegistro(this.e, {this.motivo});

  @override
  Widget build(BuildContext context) {
    final attrs = e.atributos.map((k, v) => MapEntry(k.toLowerCase().trim(), v));
    String pick(List<String> keys) =>
        keys.map((k) => (attrs[k] ?? '').trim()).firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final nome = (nomeParaExibir(e)).trim();
    final muni = pick(['municipio', 'município', 'cidade']);
    final plus = (obterPlusCode(e.atributos) ?? '').trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        border: Border.all(color: const Color(0x221565C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nome.isEmpty ? '(sem nome)' : nome, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _chipInfo('Município', muni.isEmpty ? '—' : muni),
              _chipInfo('Plus Code', plus.isEmpty ? '—' : plus),
              _chipInfo('Lat', e.coord?.lat?.toStringAsFixed(6) ?? '—'),
              _chipInfo('Lon', e.coord?.lon?.toStringAsFixed(6) ?? '—'),
            ],
          ),
          if (motivo != null && motivo!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    motivo!,
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipInfo(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x0F1565C0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        Text(v, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _ZeroStateInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ZeroStateInfo({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Painel de Lacunas (NOVO) =====
class _PainelLacunas extends StatelessWidget {
  final List<String> lacunas;
  const _PainelLacunas({required this.lacunas});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = lacunas.join(', ');

    return Card(
      color: cs.surfaceVariant.withOpacity(0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
                  children: [
                    const TextSpan(
                      text: 'Lacunas detectadas (001 até o maior sufixo encontrado): ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: txt.isEmpty ? '—' : txt),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
