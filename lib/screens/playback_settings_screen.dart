import 'package:flutter/material.dart';

import '../services/platform_service.dart';
import '../state/app_state.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<PlaybackSettingsScreen> createState() =>
      _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  bool? _pipSupported;
  bool? _pipAllowed;

  @override
  void initState() {
    super.initState();
    _refreshPipStatus();
  }

  Future<void> _refreshPipStatus() async {
    final supported = await PlatformService.isPictureInPictureSupported();
    final allowed = supported
        ? await PlatformService.isPictureInPictureAllowed()
        : false;
    if (!mounted) return;
    setState(() {
      _pipSupported = supported;
      _pipAllowed = allowed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final enabled = widget.state.pictureInPictureEnabled;
        final supported = _pipSupported;
        final allowed = _pipAllowed;
        return Scaffold(
          appBar: AppBar(title: const Text('Configuración de reproducción')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            children: [
              Text(
                'Audio y subtítulos',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Estos valores quedan guardados y se aplican al abrir películas, episodios y canales.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.volume_up_rounded),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Volumen del reproductor',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${widget.state.playbackVolume.round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      Slider(
                        value: widget.state.playbackVolume,
                        min: 0,
                        max: 200,
                        divisions: 40,
                        label: '${widget.state.playbackVolume.round()}%',
                        onChanged: widget.state.setPlaybackVolume,
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0%'),
                          Text('100% normal'),
                          Text('200%'),
                        ],
                      ),
                      if (widget.state.playbackVolume > 100) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'El volumen amplificado puede causar distorsión en algunos contenidos.',
                          style: TextStyle(color: Colors.amber),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.format_size_rounded),
                          SizedBox(width: 12),
                          Text(
                            'Tamaño de subtítulos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          (label: 'Pequeño', value: 0.75),
                          (label: 'Normal', value: 1.0),
                          (label: 'Grande', value: 1.25),
                          (label: 'Muy grande', value: 1.5),
                          (label: 'Extra', value: 1.75),
                          (label: 'Máximo', value: 2.0),
                        ].map((option) {
                          return ChoiceChip(
                            label: Text(
                              '${option.label} ${(option.value * 100).round()}%',
                            ),
                            selected: (widget.state.subtitleScale - option.value)
                                    .abs() <
                                0.01,
                            onSelected: (_) => widget.state
                                .setSubtitleScale(option.value),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Ventana flotante',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Continúa viendo el contenido en la ventana Picture-in-Picture al salir del reproductor, cambiar de aplicación o volver al catálogo.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: enabled,
                      onChanged: supported == false
                          ? null
                          : widget.state.setPictureInPictureEnabled,
                      secondary: const Icon(Icons.picture_in_picture_alt_rounded),
                      title: const Text('Picture-in-Picture'),
                      subtitle: const Text(
                        'Muestra el video en una ventana flotante al usar otra aplicación.',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      value: widget.state.pictureInPictureAutoEnter,
                      onChanged: enabled
                          ? widget.state.setPictureInPictureAutoEnter
                          : null,
                      secondary: const Icon(Icons.open_in_new_rounded),
                      title: const Text('Entrar automáticamente al salir'),
                      subtitle: const Text(
                        'Activa la ventana flotante al pulsar Atrás, Inicio o cambiar de aplicación mientras el video está reproduciéndose.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        supported == false
                            ? Icons.phone_android_rounded
                            : allowed == false
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              supported == null
                                  ? 'Comprobando compatibilidad…'
                                  : supported == false
                                      ? 'Picture-in-Picture no está disponible'
                                      : allowed == false
                                          ? 'Permiso de ventana flotante desactivado'
                                          : 'Picture-in-Picture disponible',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              supported == false
                                  ? 'Esta función requiere Android 8.0 o una versión posterior y un dispositivo compatible.'
                                  : allowed == false
                                      ? 'Android puede impedir la ventana flotante aunque esté activada dentro de AVO TV. Abre los ajustes y permite Picture-in-Picture.'
                                      : 'La ventana flotante está autorizada por Android.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.64),
                                height: 1.4,
                              ),
                            ),
                            if (supported == true) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final opened = await PlatformService
                                      .openPictureInPictureSettings();
                                  if (!opened && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No fue posible abrir los ajustes de Picture-in-Picture.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('Abrir ajustes de Android'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.picture_in_picture_alt_rounded),
                  title: Text('Picture-in-Picture al volver al catálogo'),
                  subtitle: Text(
                    'Pulsa Atrás desde el reproductor y AVO TV abrirá automáticamente la ventana flotante para que puedas navegar por la aplicación.',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
