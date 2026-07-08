import 'package:flutter/material.dart';

import '../services/iptv_api_service.dart';
import '../services/local_store.dart';
import '../state/app_state.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _store = LocalStore();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.state.startupError;
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final values = await _store.loadRememberedLogin();
    if (!mounted) return;
    _profileController.text = values['profileName'] ?? '';
    _usernameController.text = values['username'] ?? '';
  }

  @override
  void dispose() {
    _profileController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final credentials = LoginCredentials(
      profileName: _profileController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _loading = true);
    final result = await widget.state.signIn(credentials);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LoginBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tv = widget.state.isTelevision;
                final wide = tv || constraints.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: tv ? 64 : (wide ? 48 : 20),
                    vertical: tv ? 40 : 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 56,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: wide
                            ? Row(
                                children: [
                                  const Expanded(child: _BrandPanel()),
                                  const SizedBox(width: 56),
                                  SizedBox(
                                    width: tv ? 560 : 440,
                                    child: _buildForm(tv: tv),
                                  ),
                                ],
                              )
                            : _buildForm(tv: tv),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm({required bool tv}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE612161C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 48,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(tv ? 36 : 26),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CompactLogo(),
              const SizedBox(height: 28),
              Text(
                'Inicia sesión',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: tv ? 34 : null,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                tv
                    ? 'Accede con el control remoto o con un teclado conectado.'
                    : 'Usa los datos de tu servicio autorizado.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: tv ? 18 : null,
                ),
              ),
              if (tv) ...[
                const SizedBox(height: 22),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.045),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 54),
                        SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Acceso por código QR',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Próximamente. Por ahora utiliza el acceso manual.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Acceso manual',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 24),
              TextFormField(
                controller: _profileController,
                autofocus: tv,
                style: TextStyle(fontSize: tv ? 20 : null),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre del perfil',
                  hintText: 'Por ejemplo: Harvey, Sala o Recámara',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe un nombre para este perfil.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _usernameController,
                style: TextStyle(fontSize: tv ? 20 : null),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el usuario.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                style: TextStyle(fontSize: tv ? 20 : null),
                obscureText: _obscure,
                onFieldSubmitted: (_) {
                  if (!_loading) _signIn();
                },
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Escribe la contraseña.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(
                  _loading
                      ? 'Cargando canales, películas y series…'
                      : (tv ? 'Entrar a AVO TV' : 'Entrar'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : widget.state.enterDemo,
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Explorar demostración'),
              ),
              const SizedBox(height: 20),
              Text(
                'Utiliza únicamente contenido que tengas autorización para reproducir o distribuir.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _CompactLogo(),
          const SizedBox(height: 36),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'Películas, series y canales en vivo en un solo lugar.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 52,
                    height: 1.02,
                  ),
            ),
          ),
          const SizedBox(height: 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(
              'Reproduce contenido, abre temporadas y episodios, continúa donde te quedaste y recibe recomendaciones.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 18,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FeatureChip(icon: Icons.live_tv_rounded, label: 'En vivo'),
              _FeatureChip(icon: Icons.play_circle, label: 'Reproductor'),
              _FeatureChip(icon: Icons.video_library, label: 'Episodios'),
              _FeatureChip(icon: Icons.devices_rounded, label: 'Adaptable'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactLogo extends StatelessWidget {
  const _CompactLogo();

  @override
  Widget build(BuildContext context) {
    return const AvoTvLogo(size: 56, nameSize: 24);
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF060709), Color(0xFF101A16), Color(0xFF07090C)],
        ),
      ),
      child: CustomPaint(painter: _GlowPainter()),
    );
  }
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x5541E38A), Color(0x0041E38A)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.18, size.height * 0.2),
          radius: size.shortestSide * 0.55,
        ),
      );
    canvas.drawRect(Offset.zero & size, green);

    final blue = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x332D6BFF), Color(0x002D6BFF)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.84, size.height * 0.82),
          radius: size.shortestSide * 0.48,
        ),
      );
    canvas.drawRect(Offset.zero & size, blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
