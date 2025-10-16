import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <- Clipboard / ClipboardData
import 'package:url_launcher/url_launcher.dart';
import 'main.dart' show MyApp;

class ServicosPublicosPage extends StatelessWidget {
  const ServicosPublicosPage({super.key});

  /// Lista ESTÁTICA — edite à vontade.
  static const List<_Servico> _servicos = [
    _Servico(
      nome: "Prefeitura Municipal",
      endereco: "Praça Hilmar Machado de Oliveira, 102",
      telefone: "(14) 3407-6600",
      lat: -22.211890870300287,
      lon: -49.65340988394892,
    ),
    _Servico(
      nome: "Hospital Municipal",
      endereco: "R. Dr. Orlando Thiago dos Santos, 50 ",
      telefone: "(14) 3407-5066",
      lat: -22.207114651152256,
      lon: -49.64954070358212,
    ),
    _Servico(
      nome: "Delegacia de Polícia",
      endereco: "Av. Faustina, 1000",
      telefone: "(14) 3471-0222",
      lat: -22.217891870968003,
      lon: -49.66097598792869
    ),
    _Servico(
        nome: "Corpo de Bombeiros",
        endereco: "Eustáchio Scalzo, 300 ",
        telefone: "193",
        lat: -22.22276581524309,
        lon: -49.648751908699836
    ),
    _Servico(
        nome: "Defesa Civil",
        endereco: "Rua Eumene, 571",
        telefone: "(14) 99700‑2310",
        lat: -22.21708622266675,
        lon: -49.65740522783402
    ),
    _Servico(
        nome: "SAMA",
        endereco: "Rua Vital Soares, 670 ",
        telefone: "(14) 3407-6600",
        lat: -22.209724761869985, 
        lon: -49.64788722391123
    ),
  ];

  Future<void> _abrirMapa(_Servico s) async {
    Uri uri;

    if (s.lat != null && s.lon != null) {
      final lat = s.lat!.toString();
      final lon = s.lon!.toString();
      final label = Uri.encodeComponent(s.nome);

      // App nativo quando possível
      final appUri = Platform.isIOS
          ? Uri.parse("comgooglemaps://?q=$lat,$lon&center=$lat,$lon&zoom=18")
          : Uri.parse("geo:$lat,$lon?q=$lat,$lon($label)");

      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback web
      uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lon");
    } else {
      final q = Uri.encodeComponent("${s.nome}, ${s.endereco}");
      uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$q");
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _ligar(BuildContext context, String telefone) async {
    final tel = telefone.replaceAll(RegExp(r'[^0-9+]'), "");
    if (tel.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Telefone inválido.")),
        );
      }
      return;
    }

    // 1) Tenta abrir o discador nativo (tel:)
    final telUri = Uri(scheme: "tel", path: tel);
    if (await canLaunchUrl(telUri)) {
      final ok = await launchUrl(telUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }

    // 2) Fallback: tenta abrir WhatsApp (se instalado), com o número já pronto
    final waNum = tel.replaceAll('+', ''); // wa.me não usa '+'
    final waUri = Uri.parse("https://wa.me/$waNum");
    if (await canLaunchUrl(waUri)) {
      final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }

    // 3) Último recurso: copia para a área de transferência e avisa o usuário
    await Clipboard.setData(ClipboardData(text: tel));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sem app de ligação. Número copiado: $tel"),
          action: SnackBarAction(
            label: "OK",
            onPressed: () {}, // ação apenas para fechar o snackbar
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Serviços Públicos"),
        backgroundColor: MyApp.kBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _servicos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final s = _servicos[i];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // título
                  Row(
                    children: [
                      Icon(Icons.apartment, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.nome,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // endereço + botão mapa
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.endereco)),
                      IconButton(
                        tooltip: "Abrir no mapa",
                        icon: const Icon(Icons.map),
                        color: cs.primary,
                        onPressed: () => _abrirMapa(s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // telefone + botão ligar
                  Row(
                    children: [
                      const Icon(Icons.phone, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.telefone)),
                      IconButton(
                        tooltip: "Ligar",
                        icon: const Icon(Icons.call),
                        color: Colors.green,
                        onPressed: () => _ligar(context, s.telefone),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Servico {
  final String nome;
  final String endereco;
  final String telefone;
  final double? lat;
  final double? lon;

  const _Servico({
    required this.nome,
    required this.endereco,
    required this.telefone,
    this.lat,
    this.lon,
  });
}
