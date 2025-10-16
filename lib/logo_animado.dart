import 'dart:async';
import 'package:flutter/material.dart';

class LogoAnimadoPage extends StatefulWidget {
  const LogoAnimadoPage({super.key});

  @override
  State<LogoAnimadoPage> createState() => _LogoAnimadoPageState();
}

class _LogoAnimadoPageState extends State<LogoAnimadoPage>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late Animation<double> _rotationAnim;
  late AnimationController _fadeCtrl;

  String _texto = "";
  final String _mensagem = "Secretaria de Inovacao e Tecnologia";

  @override
  void initState() {
    super.initState();

    _rotationCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _rotationAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationCtrl, curve: Curves.easeOut),
    );

    _fadeCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));

    _rotationCtrl.forward();
    _fadeCtrl.forward();

    _startTyping();
  }

  void _startTyping() {
    int i = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 70), (t) {
      if (!mounted) return;
      if (i < _mensagem.length) {
        setState(() => _texto += _mensagem[i]);
        i++;
      } else {
        t.cancel();
        _goHomeAfterDelay();
      }
    });
  }

  void _goHomeAfterDelay() async {
    // pequeno respiro após terminar a digitação
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Fade bonito para a Home
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const _HomeRoutePlaceholder(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        settings: const RouteSettings(name: '/home'),
      ),
    );
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0), // azul da animação
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fadeCtrl,
              child: RotationTransition(
                turns: _rotationAnim,
                child: Image.asset(
                  'assets/logo_semit.png',
                  width: 180,
                  height: 180,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _texto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder de rota: será substituída pelo mapeamento de rota '/home' no MaterialApp.
/// Mantém o PageRouteBuilder simples e sem import circular.
class _HomeRoutePlaceholder extends StatelessWidget {
  const _HomeRoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    // usa o mapeamento de rotas do MaterialApp
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/home');
    });
    return const SizedBox.shrink();
  }
}
