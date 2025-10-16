import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UPA CRUD',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const UpaCrudPage(),
    );
  }
}

class UpaCrudPage extends StatefulWidget {
  const UpaCrudPage({super.key});

  @override
  State<UpaCrudPage> createState() => _UpaCrudPageState();
}

class _UpaCrudPageState extends State<UpaCrudPage> {
  final DatabaseReference _upasRef =
  FirebaseDatabase.instance.ref().child('upas');

  // ---- Busca/Filtro
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Propriedades Rurais (UPAs)'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openUpaForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Cadastrar'),
      ),
      body: Column(
        children: [
          // Campo de busca por nome_upa
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar por nome da UPA',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) =>
                  setState(() => _query = text.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 4),

          // Lista/Stream
          Expanded(
            child: StreamBuilder(
              stream: _upasRef.onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar: ${snapshot.error}'),
                  );
                }

                final dataEvent = snapshot.data as DatabaseEvent?;
                final raw = dataEvent?.snapshot.value;

                if (raw == null) {
                  return const Center(child: Text('Nenhuma UPA cadastrada.'));
                }

                // raw deve ser Map<String, dynamic>
                final map = Map<String, dynamic>.from(raw as Map);
                final entries = map.entries
                    .map((e) => MapEntry(
                  e.key,
                  Map<String, dynamic>.from(e.value as Map),
                ))
                    .toList()
                  ..sort((a, b) {
                    final nomeA =
                    (a.value['nome_upa'] ?? '').toString().toLowerCase();
                    final nomeB =
                    (b.value['nome_upa'] ?? '').toString().toLowerCase();
                    return nomeA.compareTo(nomeB);
                  });

                // Aplica filtro por nome_upa
                final filtered = _query.isEmpty
                    ? entries
                    : entries.where((e) {
                  final nome =
                  (e.value['nome_upa'] ?? '').toString().toLowerCase();
                  return nome.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('Nenhuma UPA encontrada para o filtro.'));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final id = filtered[index].key;
                    final json = filtered[index].value;
                    final upa = Upa.fromJson(id, json);

                    return Dismissible(
                      key: ValueKey(id),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child:
                        const Icon(Icons.delete, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child:
                        const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await _confirmDelete(context, upa);
                      },
                      onDismissed: (_) => _deleteUpa(upa.id!),
                      child: ListTile(
                        title: Text(upa.nomeUpa ?? '—'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (upa.municipio != null)
                              Text('Município: ${upa.municipio}'),
                            if (upa.codigoUpa != null)
                              Text('Código UPA: ${upa.codigoUpa}'),
                            if (upa.plusCode != null)
                              Text('Plus Code: ${upa.plusCode}'),
                          ],
                        ),
                        // Editar + Lixeira no trailing
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _openUpaForm(context, upa: upa),
                            ),
                            IconButton(
                              tooltip: 'Excluir',
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final ok =
                                await _confirmDelete(context, upa);
                                if (ok) _deleteUpa(upa.id!);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Upa upa) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Rota'),
        content: Text(
            'Deseja realmente excluir "${upa.nomeUpa ?? upa.id}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    ) ??
        false;
  }

  Future<void> _deleteUpa(String id) async {
    await _upasRef.child(id).remove();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rota excluída.')));
    }
  }

  Future<void> _openUpaForm(BuildContext context, {Upa? upa}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => UpaForm(
        onSave: (payload) async {
          if (upa == null || upa.id == null) {
            // CREATE (push)
            final newRef = _upasRef.push();
            await newRef.set(payload);
          } else {
            // UPDATE
            await _upasRef.child(upa.id!).update(payload);
          }
        },
        initial: upa?.toJson(),
      ),
    );
  }
}

class UpaForm extends StatefulWidget {
  const UpaForm({
    super.key,
    required this.onSave,
    this.initial,
  });

  final Future<void> Function(Map<String, dynamic> payload) onSave;
  final Map<String, dynamic>? initial;

  @override
  State<UpaForm> createState() => _UpaFormState();
}

class _UpaFormState extends State<UpaForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController codigoUpa;
  late final TextEditingController globalId;
  late final TextEditingController municipio;
  late final TextEditingController nomeUpa;
  late final TextEditingController objectId;
  late final TextEditingController plusCode;
  late final TextEditingController tipoEmpreendimento;
  late final TextEditingController x;
  late final TextEditingController y;

  @override
  void initState() {
    super.initState();
    codigoUpa =
        TextEditingController(text: widget.initial?['codigo_upa'] ?? '');
    globalId = TextEditingController(
        text: widget.initial?['geometry']?['globalid'] ??
            widget.initial?['globalid'] ??
            '');
    municipio =
        TextEditingController(text: widget.initial?['municipio'] ?? '');
    nomeUpa = TextEditingController(text: widget.initial?['nome_upa'] ?? '');
    objectId = TextEditingController(text: widget.initial?['objectid'] ?? '');
    plusCode =
        TextEditingController(text: widget.initial?['plus_code'] ?? '');
    tipoEmpreendimento = TextEditingController(
        text: widget.initial?['tipo_empreendimento'] ?? 'Propriedade Rural');
    x = TextEditingController(text: widget.initial?['x']?.toString() ?? '');
    y = TextEditingController(text: widget.initial?['y']?.toString() ?? '');

  }

  @override
  void dispose() {
    codigoUpa.dispose();
    globalId.dispose();
    municipio.dispose();
    nomeUpa.dispose();
    objectId.dispose();
    plusCode.dispose();
    tipoEmpreendimento.dispose();
    x.dispose();
    y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.initial == null
                            ? 'Cadastrar UPA'
                            : 'Editar UPA',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                _LabeledField(
                  label: 'Código UPA',
                  controller: codigoUpa,
                  validator: _required,
                ),
                _LabeledField(
                  label: 'Nome da UPA',
                  controller: nomeUpa,
                  validator: _required,
                ),
                _LabeledField(
                  label: 'Município',
                  controller: municipio,
                ),
                _LabeledField(
                  label: 'Plus Code',
                  controller: plusCode,
                ),
                _LabeledField(
                  label: 'Tipo de Empreendimento',
                  controller: tipoEmpreendimento,
                ),
                _LabeledField(
                  label: 'ObjectID',
                  controller: objectId,
                ),
                _LabeledField(
                  label: 'GlobalID',
                  controller: globalId,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'X',
                        controller: x,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: 'Y',
                        controller: y,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _onSubmit,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return 'Obrigatório';
    return null;
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = {
      'codigo_upa': codigoUpa.text.trim(),
      'geometry': {
        'globalid': globalId.text.trim(),
      },
      'municipio': municipio.text.trim(),
      'nome_upa': nomeUpa.text.trim(),
      'objectid': objectId.text.trim(),
      'plus_code': plusCode.text.trim(),
      'tipo_empreendimento': tipoEmpreendimento.text.trim(),
      'x': x.text.trim(),
      'y': y.text.trim(),
    };

    try {
      await widget.onSave(payload);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar: $e')),
      );
    }
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class Upa {
  final String? id;
  final String? codigoUpa;
  final String? municipio;
  final String? nomeUpa;
  final String? objectid;
  final String? plusCode;
  final String? tipoEmpreendimento;
  final String? x;
  final String? y;
  final String? globalId;

  Upa({
    this.id,
    this.codigoUpa,
    this.municipio,
    this.nomeUpa,
    this.objectid,
    this.plusCode,
    this.tipoEmpreendimento,
    this.x,
    this.y,
    this.globalId,
  });

  factory Upa.fromJson(String id, Map<String, dynamic> json) {
    // Suporta tanto geometry.globalid quanto globalid direto
    String? global;
    if (json['geometry'] is Map) {
      final g = Map<String, dynamic>.from(json['geometry']);
      global = g['globalid']?.toString();
    } else {
      global = json['globalid']?.toString();
    }

    return Upa(
      id: id,
      codigoUpa: json['codigo_upa']?.toString(),
      municipio: json['municipio']?.toString(),
      nomeUpa: json['nome_upa']?.toString(),
      objectid: json['objectid']?.toString(),
      plusCode: json['plus_code']?.toString(),
      tipoEmpreendimento: json['tipo_empreendimento']?.toString(),
      x: json['x']?.toString(),
      y: json['y']?.toString(),
      globalId: global,
    );
  }

  Map<String, dynamic> toJson() => {
    'codigo_upa': codigoUpa,
    'geometry': {'globalid': globalId},
    'municipio': municipio,
    'nome_upa': nomeUpa,
    'objectid': objectid,
    'plus_code': plusCode,
    'tipo_empreendimento': tipoEmpreendimento,
    'x': x,
    'y': y,
  };
}
