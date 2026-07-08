import 'dart:io';

import 'package:avo_tv/data/demo_catalog.dart';
import 'package:avo_tv/models/media_item.dart';
import 'package:avo_tv/models/live_recording.dart';
import 'package:avo_tv/models/series_details.dart';
import 'package:avo_tv/services/catalog_search_service.dart';
import 'package:avo_tv/services/iptv_api_service.dart';
import 'package:avo_tv/services/local_store.dart';
import 'package:avo_tv/services/server_directory_service.dart';
import 'package:avo_tv/core/provider_config.dart';
import 'package:avo_tv/screens/activity_screen.dart';
import 'package:avo_tv/state/app_state.dart';
import 'package:avo_tv/widgets/media_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('la búsqueda inteligente tolera errores sencillos', () {
    final search = CatalogSearchService(demoCatalog);
    final result = search.search('orbitaa final');

    expect(result.items, isNotEmpty);
    expect(result.items.first.title, contains('Órbita'));
    expect(result.usedFuzzyMatching, isTrue);
  });

  test('la búsqueda encuentra título, género y reparto', () {
    final search = CatalogSearchService(demoCatalog);

    expect(search.search('espacio').items, isNotEmpty);
    expect(search.search('fantasía').items, isNotEmpty);
    expect(search.search('Elena Cruz').items, isNotEmpty);
  });

  test('la búsqueda inteligente puede limitarse a películas o series', () {
    final search = CatalogSearchService(demoCatalog);

    final movies = search.search('orbitaa', type: MediaType.movie).items;
    final series = search.search('cronicas', type: MediaType.series).items;

    expect(movies, isNotEmpty);
    expect(movies.every((item) => item.type == MediaType.movie), isTrue);
    expect(series, isNotEmpty);
    expect(series.every((item) => item.type == MediaType.series), isTrue);
  });

  test('el catálogo de demostración incluye películas y series', () {
    expect(demoCatalog.any((item) => item.type == MediaType.movie), isTrue);
    expect(demoCatalog.any((item) => item.type == MediaType.series), isTrue);
  });

  test('las credenciales conservan el perfil y una configuración válida', () {
    const credentials = LoginCredentials(
      profileName: 'Sala',
      username: 'usuario',
      password: 'clave',
    );

    expect(credentials.baseUri.scheme, isNotEmpty);
    expect(credentials.baseUri.host, isNotEmpty);
    expect(credentials.baseUri.port, greaterThan(0));
    expect(credentials.profileName, 'Sala');
  });

  test('SeriesDetails ordena temporadas y encuentra episodios', () {
    const episode = EpisodeItem(
      id: 'episode-10',
      title: 'Inicio',
      seasonNumber: 2,
      episodeNumber: 1,
      description: 'Prueba',
      durationLabel: '40 min',
      imageUrl: '',
      streamUrls: ['https://example.com/video.mp4'],
    );
    const details = SeriesDetails(
      seriesId: '10',
      seasons: {
        2: [episode],
        1: [],
      },
    );

    expect(details.seasonNumbers, [1, 2]);
    expect(details.findEpisode('episode-10'), episode);
  });

  testWidgets('MediaCard admite ancho infinito dentro de una cuadrícula', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 420,
            child: MediaCard(
              item: demoCatalog.first,
              state: state,
              width: double.infinity,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(demoCatalog.first.title), findsOneWidget);
  });

  test('se puede quitar un título de Continuar viendo', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState()..enterDemo();
    final movie = demoCatalog.firstWhere(
      (item) => item.type == MediaType.movie,
    );

    await state.savePlaybackProgress(movie, 0.35);
    expect(state.continueWatching.map((item) => item.id), contains(movie.id));

    await state.removeFromContinueWatching(movie);
    expect(
      state.continueWatching.map((item) => item.id),
      isNot(contains(movie.id)),
    );
    expect(state.history, isNot(contains(movie.id)));
  });

  test('borrar historial conserva el catálogo y elimina el progreso', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState()..enterDemo();
    final movie = demoCatalog.firstWhere(
      (item) => item.type == MediaType.movie,
    );

    await state.savePlaybackProgress(movie, 0.55);
    expect(state.hasPlaybackActivity, isTrue);

    await state.clearPlaybackHistory();
    expect(state.hasPlaybackActivity, isFalse);
    expect(state.catalog, isNotEmpty);
  });

  test('el reproductor no contiene controles estimados de créditos', () {
    final source = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Saltar créditos')));
    expect(source, isNot(contains('Posible postcréditos')));
    expect(source, isNot(contains('_showCreditsActions')));
  });

  test('Mi actividad contiene la administración del historial', () {
    final source = File(
      'lib/screens/activity_screen.dart',
    ).readAsStringSync();

    expect(source, contains("title: const Text('Mi actividad')"));
    expect(source, contains("'Historial y progreso'"));
    expect(source, contains("'Borrar todo “Continuar viendo”'"));
    expect(source, contains("'Restablecer progreso de películas'"));
    expect(source, contains("'Restablecer progreso de series'"));
    expect(source, contains("'Borrar historial de reproducción'"));
  });

  test('las preferencias de Picture-in-Picture se conservan', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore();

    expect(await store.loadPictureInPictureEnabled(), isTrue);
    expect(await store.loadPictureInPictureAutoEnter(), isTrue);

    await store.savePictureInPictureEnabled(false);
    await store.savePictureInPictureAutoEnter(false);

    expect(await store.loadPictureInPictureEnabled(), isFalse);
    expect(await store.loadPictureInPictureAutoEnter(), isFalse);
  });

  test('v0.6.8 conserva PiP y prepara la experiencia de TV', () {
    final player = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();
    final androidSetup = File(
      'tool/prepare_android.py',
    ).readAsStringSync();

    expect(player, contains('_returnToCatalogWithPip'));
    expect(player, isNot(contains('_buildMiniPlayerOverlay')));
    expect(player, contains('_showSleepTimerMenu'));
    expect(player, contains('_autoNextSeconds = 10'));
    expect(player, contains('Reproducir ahora'));
    expect(player, contains("child: const Text('Cancelar')"));
    expect(androidSetup, contains('class PlayerActivity'));
    expect(androidSetup, contains('getDartEntrypointFunctionName'));
    expect(androidSetup, contains('android:supportsPictureInPicture="true"'));
    expect(androidSetup, contains('setAutoEnterEnabled'));
    expect(androidSetup, contains('PipActionReceiver'));
    expect(androidSetup, contains('android.software.leanback'));
    expect(androidSetup, contains('LEANBACK_LAUNCHER'));
    expect(androidSetup, contains('isTelevision'));
  });

  test('el volumen y el tamaño de subtítulos se conservan', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore();

    expect(await store.loadPlaybackVolume(), 100);
    expect(await store.loadSubtitleScale(), 1);

    await store.savePlaybackVolume(175);
    await store.saveSubtitleScale(1.5);

    expect(await store.loadPlaybackVolume(), 175);
    expect(await store.loadSubtitleScale(), 1.5);
  });

  test('el reproductor incluye amplificación y control de subtítulos', () {
    final source = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();

    expect(source, contains("setProperty('volume-max', '200')"));
    expect(source, contains('_showVolumeMenu'));
    expect(source, contains('_showSubtitleSizeMenu'));
    expect(
      source,
      contains('fontSize: (widget.appState.isTelevision ? 32 : 28)'),
    );
  });

  test('v0.6.8 incluye TV en vivo premium y cambio seguro en PiP', () {
    final live = File('lib/screens/live_screen.dart').readAsStringSync();
    final platform = File(
      'lib/services/platform_service.dart',
    ).readAsStringSync();
    final playerApp = File('lib/player_app.dart').readAsStringSync();
    final androidSetup = File('tool/prepare_android.py').readAsStringSync();

    expect(live, contains('Televisión en vivo'));
    expect(live, contains('Todos los canales'));
    expect(live, contains('Vistos recientemente'));
    expect(live, contains('Video('));
    expect(live, contains('hasActivePlayer'));
    expect(platform, contains("invokeMethod<bool>('hasActivePlayer')"));
    expect(platform, contains("case 'replacePlayerPayload'"));
    expect(playerApp, contains('setPlayerReplacementHandler'));
    expect(androidSetup, contains('fun replacePayload(payload: String)'));
    expect(androidSetup, contains('"hasActivePlayer"'));
    expect(androidSetup, isNot(contains('postDelayed({ launchPlayer() }, 350)')));
  });

  test('el historial de TV en vivo conserva el último canal abierto', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState()..enterDemo();
    final channel = state.liveChannels.first;

    await state.markLiveChannelOpened(channel);

    expect(state.recentlyWatchedLive, isNotEmpty);
    expect(state.recentlyWatchedLive.first.id, channel.id);
  });


  test('la metadata de grabación conserva título, canal y tamaño', () {
    final recording = LiveRecording.fromMap({
      'id': 'rec-1',
      'sourceChannelId': 'canal-9',
      'title': 'México vs. Argentina',
      'channelTitle': 'Deportes 1',
      'posterUrl': 'https://example.com/logo.png',
      'localPath': '/data/user/0/mx.avotv/recordings/partido.ts',
      'startedAt': 1000,
      'endedAt': 2000,
      'durationSeconds': 7200,
      'sizeBytes': 2048,
      'status': 'completed',
      'errorMessage': '',
      'maxDurationMinutes': 180,
    });

    expect(recording.title, 'México vs. Argentina');
    expect(recording.channelTitle, 'Deportes 1');
    expect(recording.sizeBytes, 2048);
    expect(recording.canPlay, isTrue);
    expect(recording.isActive, isFalse);
  });

  test('v0.6.8 incluye grabación privada en segundo plano', () {
    final platform = File(
      'lib/services/platform_service.dart',
    ).readAsStringSync();
    final live = File('lib/screens/live_screen.dart').readAsStringSync();
    final library = File('lib/screens/library_screen.dart').readAsStringSync();
    final recordings = File(
      'lib/screens/recordings_screen.dart',
    ).readAsStringSync();
    final androidSetup = File('tool/prepare_android.py').readAsStringSync();

    expect(platform, contains("'startLiveRecording'"));
    expect(platform, contains("'stopLiveRecording'"));
    expect(platform, contains("'listLiveRecordings'"));
    expect(live, contains('Nombre de la grabación'));
    expect(live, contains('México vs. Argentina'));
    expect(library, contains('Mis grabaciones'));
    expect(recordings, contains('Reproducir'));
    expect(recordings, contains('Eliminar'));
    expect(androidSetup, contains('class RecordingService'));
    expect(androidSetup, contains('FOREGROUND_SERVICE_DATA_SYNC'));
    expect(androidSetup, contains('START_REDELIVER_INTENT'));
    expect(androidSetup, contains('override fun onTimeout'));
    expect(androidSetup, contains('sizeBeforeCandidate'));
    expect(androidSetup, contains('STORAGE_RESERVE_BYTES'));
    expect(androidSetup, contains('La señal utiliza cifrado'));
  });


  test('v0.6.9 valida y ordena la configuración remota', () {
    final snapshot = ServerDirectorySnapshot.tryParse({
      'schema': 1,
      'version': 4,
      'servers': [
        {
          'id': 'normal',
          'baseUrl': 'http://avotv.online:8080',
          'priority': 2,
          'enabled': true,
        },
        {
          'id': 'plus',
          'baseUrl': 'http://ultratvsv.site:80',
          'priority': 1,
          'enabled': true,
        },
      ],
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.servers.map((item) => item.id), ['plus', 'normal']);
    expect(snapshot.servers.first.baseUri.port, 80);
  });

  test('las credenciales guardan el servicio detectado sin mostrarlo en login', () {
    const endpoint = ProviderEndpoint(
      id: 'plus',
      scheme: 'http',
      host: 'ultratvsv.site',
      port: 80,
      priority: 1,
    );
    const original = LoginCredentials(
      profileName: 'Sala',
      username: 'usuario',
      password: 'clave',
    );
    final resolved = original.forProvider(endpoint);
    final restored = LoginCredentials.fromMap(resolved.toMap());
    final loginSource = File('lib/screens/login_screen.dart').readAsStringSync();

    expect(restored.serverId, 'plus');
    expect(restored.baseUri.host, 'ultratvsv.site');
    expect(restored.baseUri.port, 80);
    expect(loginSource, isNot(contains('Servidor:')));
    expect(loginSource, isNot(contains('DNS')));
  });

  test('v0.6.9 incluye configuración remota, caché y respaldo local', () {
    final configSource = File(
      'lib/core/provider_config.dart',
    ).readAsStringSync();
    final directorySource = File(
      'lib/services/server_directory_service.dart',
    ).readAsStringSync();
    final apiSource = File(
      'lib/services/iptv_api_service.dart',
    ).readAsStringSync();

    expect(configSource, contains('sammfloore.github.io/avotv-config'));
    expect(configSource, contains('raw.githubusercontent.com/sammfloore'));
    expect(configSource, contains("id: 'plus'"));
    expect(configSource, contains("id: 'normal'"));
    expect(directorySource, contains('avo_tv_server_directory_v1'));
    expect(directorySource, contains('_loadCached'));
    expect(directorySource, contains('ProviderConfig.fallbackServers'));
    expect(apiSource, contains('loadCandidates'));
    expect(apiSource, contains('forProvider(endpoint)'));
  });


  test('la detección automática continúa con el segundo servicio válido', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.host == 'config.example') {
        return http.Response(
          '''{
            "schema": 1,
            "version": 7,
            "servers": [
              {"id":"plus","baseUrl":"http://ultratvsv.site:80","priority":1,"enabled":true},
              {"id":"normal","baseUrl":"http://avotv.online:8080","priority":2,"enabled":true}
            ]
          }''',
          200,
        );
      }
      if (request.url.host == 'ultratvsv.site') {
        return http.Response(
          '{"user_info":{"auth":0,"status":"Disabled"}}',
          200,
        );
      }
      if (request.url.host == 'avotv.online') {
        return http.Response(
          '''{
            "user_info": {
              "auth": 1,
              "status": "Active",
              "username": "usuario",
              "allowed_output_formats": ["ts", "m3u8"]
            },
            "server_info": {
              "server_protocol": "http",
              "url": "avotv.online",
              "port": "8080"
            }
          }''',
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final directory = ServerDirectoryService(
      client: client,
      remoteConfigUris: [Uri.parse('https://config.example/avotv-config.json')],
    );
    final api = IptvApiService(client: client, serverDirectory: directory);

    final result = await api.authenticate(
      const LoginCredentials(
        profileName: 'Sala',
        username: 'usuario',
        password: 'clave',
      ),
    );

    expect(result.success, isTrue);
    expect(result.resolvedCredentials?.serverId, 'normal');
    expect(result.resolvedCredentials?.baseUri.host, 'avotv.online');
  });

}
