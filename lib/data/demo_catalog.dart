import '../models/media_item.dart';

const demoCatalog = <MediaItem>[
  MediaItem(
    id: 'movie-orbita-1',
    title: 'Órbita Final',
    type: MediaType.movie,
    year: 2026,
    rating: 8.7,
    description:
        'Una piloto debe atravesar una tormenta espacial para recuperar una estación científica perdida.',
    posterUrl:
        'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=1600&q=85',
    genres: ['Ciencia ficción', 'Aventura'],
    cast: ['Elena Cruz', 'Marco Vidal'],
    keywords: ['espacio', 'misión', 'futuro', 'nave'],
    durationLabel: '2 h 08 min',
    franchise: 'Órbita',
    isNew: true,
  ),
  MediaItem(
    id: 'series-orbita-2',
    title: 'Órbita: Estación Cero',
    type: MediaType.series,
    year: 2026,
    rating: 9.1,
    description:
        'Antes de la misión final, un equipo internacional descubre señales imposibles bajo la superficie lunar.',
    posterUrl:
        'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1444703686981-a3abbc4d4fe3?auto=format&fit=crop&w=1600&q=85',
    genres: ['Ciencia ficción', 'Misterio'],
    cast: ['Elena Cruz', 'Rafael Soto'],
    keywords: ['luna', 'estación', 'misterio', 'espacio'],
    durationLabel: '8 episodios',
    franchise: 'Órbita',
    isNew: true,
  ),
  MediaItem(
    id: 'movie-ciudad-luz',
    title: 'La Ciudad de Luz',
    type: MediaType.movie,
    year: 2025,
    rating: 8.2,
    description:
        'Una fotógrafa encuentra una antigua carta que transforma su viaje por una ciudad europea.',
    posterUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1499856871958-5b9627545d1a?auto=format&fit=crop&w=1600&q=85',
    genres: ['Drama', 'Romance'],
    cast: ['Sofía Luna', 'Daniel Ferrer'],
    keywords: ['viaje', 'fotografía', 'amor', 'carta'],
    durationLabel: '1 h 54 min',
    isNew: false,
  ),
  MediaItem(
    id: 'series-codigo-sombra',
    title: 'Código Sombra',
    type: MediaType.series,
    year: 2026,
    rating: 8.9,
    description:
        'Una analista de seguridad descubre que el mayor ataque digital de la historia comenzó dentro de su propia empresa.',
    posterUrl:
        'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1558494949-ef010cbdcc31?auto=format&fit=crop&w=1600&q=85',
    genres: ['Suspenso', 'Tecnología'],
    cast: ['Valeria Norte', 'Iván Reyes'],
    keywords: ['hacker', 'código', 'empresa', 'conspiración'],
    durationLabel: '10 episodios',
    isNew: true,
  ),
  MediaItem(
    id: 'movie-reino-niebla',
    title: 'El Reino de la Niebla',
    type: MediaType.movie,
    year: 2024,
    rating: 8.4,
    description:
        'Una joven guardiana debe unir tres territorios antes de que una niebla antigua borre sus recuerdos.',
    posterUrl:
        'https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=1600&q=85',
    genres: ['Fantasía', 'Aventura'],
    cast: ['Mara Sol', 'Tomás Valle'],
    keywords: ['reino', 'magia', 'bosque', 'leyenda'],
    durationLabel: '2 h 17 min',
    franchise: 'Reino de la Niebla',
  ),
  MediaItem(
    id: 'series-reino-niebla',
    title: 'Crónicas de la Niebla',
    type: MediaType.series,
    year: 2025,
    rating: 8.6,
    description:
        'Las historias de quienes protegieron el reino mucho antes del regreso de la guardiana.',
    posterUrl:
        'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1600&q=85',
    genres: ['Fantasía', 'Drama'],
    cast: ['Tomás Valle', 'Lucía Prado'],
    keywords: ['reino', 'leyenda', 'montaña', 'magia'],
    durationLabel: '12 episodios',
    franchise: 'Reino de la Niebla',
  ),
  MediaItem(
    id: 'movie-ultima-vuelta',
    title: 'La Última Vuelta',
    type: MediaType.movie,
    year: 2025,
    rating: 7.9,
    description:
        'Un piloto retirado vuelve a competir para ayudar al equipo que lo vio crecer.',
    posterUrl:
        'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1600&q=85',
    genres: ['Acción', 'Drama'],
    cast: ['Bruno Vega', 'Ana Torres'],
    keywords: ['carreras', 'autos', 'equipo', 'velocidad'],
    durationLabel: '1 h 48 min',
  ),
  MediaItem(
    id: 'series-archivo-13',
    title: 'Archivo 13',
    type: MediaType.series,
    year: 2024,
    rating: 8.3,
    description:
        'Dos investigadores reabren casos que fueron cerrados por razones que nadie quiere explicar.',
    posterUrl:
        'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1509248961158-e54f6934749c?auto=format&fit=crop&w=1600&q=85',
    genres: ['Misterio', 'Crimen'],
    cast: ['Nora Campos', 'Leo Méndez'],
    keywords: ['investigación', 'archivo', 'casos', 'detectives'],
    durationLabel: '16 episodios',
  ),
  MediaItem(
    id: 'movie-cocina-medianoche',
    title: 'Cocina de Medianoche',
    type: MediaType.movie,
    year: 2026,
    rating: 8.0,
    description:
        'Una chef abre un pequeño restaurante nocturno donde cada platillo cambia la vida de un cliente.',
    posterUrl:
        'https://images.unsplash.com/photo-1515003197210-e0cd71810b5f?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1600&q=85',
    genres: ['Comedia', 'Drama'],
    cast: ['Paula Ríos', 'Mateo Gil'],
    keywords: ['comida', 'chef', 'restaurante', 'amistad'],
    durationLabel: '1 h 42 min',
    isNew: true,
  ),
  MediaItem(
    id: 'series-planeta-vivo',
    title: 'Planeta Vivo',
    type: MediaType.series,
    year: 2025,
    rating: 9.0,
    description:
        'Una mirada cinematográfica a los ecosistemas más sorprendentes y frágiles del planeta.',
    posterUrl:
        'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1600&q=85',
    genres: ['Documental', 'Naturaleza'],
    cast: ['Narración de Alma Ruiz'],
    keywords: ['animales', 'naturaleza', 'planeta', 'documental'],
    durationLabel: '6 episodios',
  ),
  MediaItem(
    id: 'movie-risas-barrio',
    title: 'Risas del Barrio',
    type: MediaType.movie,
    year: 2023,
    rating: 7.7,
    description:
        'Tres vecinos organizan un festival improvisado para salvar el parque de su colonia.',
    posterUrl:
        'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=1600&q=85',
    genres: ['Comedia', 'Familiar'],
    cast: ['Diego Mora', 'Clara Paz'],
    keywords: ['amigos', 'barrio', 'festival', 'familia'],
    durationLabel: '1 h 36 min',
  ),
  MediaItem(
    id: 'series-mar-adentro',
    title: 'Mar Adentro',
    type: MediaType.series,
    year: 2026,
    rating: 8.5,
    description:
        'La tripulación de un barco científico encuentra una señal debajo de una fosa oceánica.',
    posterUrl:
        'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=700&q=85',
    backdropUrl:
        'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=1600&q=85',
    genres: ['Aventura', 'Misterio'],
    cast: ['Irene Mar', 'Pablo Serra'],
    keywords: ['océano', 'barco', 'expedición', 'señal'],
    durationLabel: '8 episodios',
    isNew: true,
  ),
];
