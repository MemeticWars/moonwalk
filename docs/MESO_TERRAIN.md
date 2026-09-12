# Orbita, mezo i powierzchnia

Warstwa mezo korzysta z NASA LRO LOLA `ldem_64_uint.tif`, 23040 × 11520 próbek,
64 px/stopień (473,80 m/px na równiku). Źródło i uznanie autorstwa:
[NASA Scientific Visualization Studio / CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/).
To model wysokości, nie fotografia ani klasyfikacja pokrycia. Dane 2 m istnieją
tylko w opracowanych sektorach; mniejszy detal poza nimi jest proceduralny.

`tools/prepare_meso_dem.mjs` dzieli źródłowy TIFF na 1035 kafli 512 × 512,
uint16 little endian. Wysokość to `wartość * 0,5 - 10000` metrów względem
sfery o promieniu 1737400 m. Gra czyta potrzebne kafle z dysku i utrzymuje
cache LRU najwyżej 48 kafli (24 MiB). Pełna mapa pozostaje na dysku, poza RAM.
To lokalny zestaw danych; istniejący adapter GeoServera nadal obsługuje sektory
lokalne i nie jest wymagany do tej warstwy.

Sfera składa się z sześciu ścian quadtree, bez osobliwego zagęszczenia siatki
na biegunach. Kafle są dokładniejsze bliżej kamery. Poprzednia geometria
pozostaje do czasu przygotowania zastępstwa; nowe wierzchołki narastają przez
0,65 s. Nie stosujemy sześciokrotnego wyolbrzymienia wysokości na globie.

Przy podejściu kamera i sfera przechodzą do lokalnego układu w metrach,
z zachowaniem projekcji. Nie ma wygaszania ekranu. Dokładna rzeźba lokalna
narasta dopiero między 1200 a 400 m nad celem. Siatka do chodzenia pojawia się
poniżej 600 m po przygotowaniu kafli. Sfera pozostaje widoczna jako otoczenie
podczas całego ukośnego podejścia, również po przejęciu kamery przez postać.

Podejście obejmuje 14 s zejścia pionowego do 8 km, 14 s szerokiego zakrętu
oraz 38 s lotu do celu z odległości 8 km. Ostatnie 10 s prowadzi do kamery
postaci. Ruch zwalnia, gdy kolejka LOD jest duża; wysokość kamery uwzględnia
teren po drodze. Kierunek patrzenia zmienia się ciągle, dając ponad 30 s
widoku ukośnego zamiast patrzenia wyłącznie pionowo w dół.

Najgrubszy glob ma normalne obliczone z wysokości i rzuca cienie. Kafle mezo
mają osobną geometrię cienia, bez pionowych krawędzi maskujących łączenia LOD.
Geometria widoczna i geometria cienia korzystają z tego samego narastania detalu.
Zasięg kaskad cieni jest wyrażony w promieniach Księżyca na orbicie, a w metrach
podczas podejścia i na powierzchni. Kierunek Słońca jest zachowany w układzie
globu i przeliczany na układ lokalny: dowolna nowa lokalizacja może być także
po nocnej stronie. Globalne dane i proceduralny detal działają poza miastami.

Barwa globu i powierzchni pochodzi z tej samej mapy regionalnej. Narzędzie
`godot/tests/bake_regional_albedo.gd` wybiera jaśniejsze środkowe próbki
(55–85 percentyl) z mozaiki LROC, uśrednia je i ogranicza kontrast.
Wynik ma 128 × 64 piksele; nie zawiera fotograficznych kształtów cieni.
Ortomozaiki sektorów nie są nakładane na grunt. Oświetlenie pochodzi ze sceny,
a drobna faktura regolitu z materiału proceduralnego. Jest to przybliżenie
barwy do gry, nie naukowa rekonstrukcja albedo.

Sprawdzenie:

- `--headless --path godot --script res://tests/approach_path_test.gd`:
  pionowy początek, dystans 8 km, długi widok ukośny i ciągłość etapów.

- `--headless --path godot --script res://tests/meso_data_test.gd`: próbki z TIFF,
  brzegi kafli, antymeridian, limit cache i pokrycie sześciu ścian LOD.
- `--headless --path godot --script res://tests/terrain_transition_test.gd`:
  granice sektora 2 m, zgodność kolizji i dalekie kafle.
- `--headless --path godot --script res://tests/orbital_travel_test.gd`:
  dowolne punkty i powrót do Tycho.
- `--path godot --script res://tests/meso_visual_test.gd`: zrzuty Vulkan
  `artifacts/meso_*.png` i kontrola braku centralnego detalu w szerokim widoku.
