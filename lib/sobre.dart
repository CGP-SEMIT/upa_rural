import 'package:flutter/material.dart';

class SobrePage extends StatelessWidget {
  const SobrePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sobre "),
        backgroundColor: const Color(0xFF1565C0),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: const [
            Text(
              "Rotas Rurais",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
              ),
            ),
            SizedBox(height: 12),
            Text(
              "O Aplicativo Rotas Rurais foi desenvolvido pela Secretaria de Inovação e Tecnologia da Prefeitura Municipal de Garça, com o objetivo de facilitar a identificação e localização de propriedades rurais no município.",
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              "A ferramenta foi desenvolvida para oferecer suporte estratégico a ambulâncias, Polícia Militar, Corpo de Bombeiros e equipes da Prefeitura, além de contribuir para o atendimento de fornecedores de insumos agrícolas e demais prestadores de serviços.",
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            SizedBox(height: 20),
            Divider(),
            SizedBox(height: 8),
            Text(
              "Contato",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Endereço:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Rua Coronel Joaquim Piza, 192 – Garça/SP"),
            SizedBox(height: 8),
            Text(
              "Telefone:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("(14) 3407-6618"),
            SizedBox(height: 8),
            Text(
              "E-mail:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("semit@garca.sp.gov.br"),
          ],
        ),
      ),
    );
  }
}
