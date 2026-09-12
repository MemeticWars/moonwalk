# Autostrady

Stary model Meshy, jego tekstury oraz ręcznie narysowany miniaturowy trójkąt tras zostały usunięte. Nowe assety powstają w `godot/scripts/highway_mesh.gd`: betonowy pomost grubości 0,7 m, stalowe barierki, oznakowanie i odsłonięte podpory. Gotowe sceny `highway_straight.scn`, `highway_curve.scn` i `highway_incline.scn` znajdują się w `godot/assets/roads`. Generator: `godot/tools/build_highways.gd`. Gra używa tego samego generatora, dopasowując geometrię do terenu.

Jezdnia ma dwukrotność zmierzonej szerokości wizualnego modelu łazika (wraz z kołami i dopasowaną kabiną) w metrach świata. Model łazika jest skalowany jedną stałą `ROVER_SCALE` w `lunar_lorry.gd` — donor z Meshy.ai importuje się przy ~0,12 m, więc stała celuje w ~5,0 m długości pojazdu. Obecnie łazik ma ~3,0 m szerokości, więc jezdnia ~6,0 m. Zewnętrzne pobocza po 0,4 m. Skala postaci działa analogicznie: `theia.gd` mierzy rzeczywisty AABB modelu w `_ready` i skaluje go do `REFERENCE_HEIGHT_M` (2 m), zamiast zakładać stałą wysokość źródła.

Sąsiednie panele dzielą dokładnie te same przekroje i normalne. Nie ma zakładek ani poziomych stopni. Kolizja pochodzi z trójkątów pomostu; malowanie nie dodaje dodatkowej płaszczyzny kolizji. Dalszy poziom szczegółowości zachowuje jezdnię i usuwa drobne słupki. Barierki i podpory są grupowane według materiału i kafla.

## Sieć i kryterium długości

`highway_network.gd` sprawdza wszystkie 91 nieuporządkowanych par 14 lokacji. Łączy każdą parę o odległości **ściśle mniejszej niż 700 km**, bez duplikatów. Odległość liczy wzorem haversine na kuli o promieniu 1737,4 km, z roboczych współrzędnych w `colonies.json`. Aktualne dane dają 9 tras. Dokładnie 700 km jest wykluczone. Stare odległości z symulacji gospodarczej nie określają tej sieci.

Glob pokazuje najkrótsze łuki wielkiego koła między faktycznymi markerami kolonii, z zasłanianiem po drugiej stronie globu. `world_routes.json` jest eksportem tego samego algorytmu, a nie drugim ręcznie utrzymywanym źródłem danych.

## Planowanie lokalne

W terenie punktem wyjścia jest krótka trasa zgodna z kierunkiem do celu. A* minimalizuje koszt długości ważonej nachyleniem, zagłębieniami i odchyleniem od korytarza. Następnie wyrównywane są zakręty dla szerokiej jezdni, a profil wysokości uwzględnia teren na całej szerokości. Obustronna obwiednia ogranicza podjazdy i zjazdy do 6%; profil jest wygładzany. To jawne kryteria projektowe gry, nie certyfikacja drogowa ani dowód globalnego optimum po wygładzeniu trasy.

Projekt nadal udostępnia jedynie lokalny sektor Silesii. W nim generowane są początkowe korytarze do Lubin Deep i Shackleton Ice, do 1400 m od punktu bazowego. Wyloty są oddzielone przy placu kolonii, aby pomosty nie nakładały się na siebie. Odległe kolonie nie są odwzorowywane w miniaturze obok Silesii. **Pełna sieć jest na globie; jazda pomiędzy wszystkimi koloniami wymaga rozbudowy istniejącego systemu sektorów i przejść między nimi.** Lokalny A* i profil nie oznaczają zweryfikowania całych setek kilometrów na szczegółowym DEM-ie.

## Sprawdzenie

Uruchamiaj lokalnym `tools/godot/Godot_v4.6.1-stable_win64_console.exe`, z `--path godot` oraz `--log-file` wskazującym zapisywalny plik:

- `--headless --script res://tests/highway_test.gd`: próg 700 km, kompletność par, ciągłość przekrojów i normalnych, nachylenie, zgodność LOD oraz rzeczywisty raycast w nawierzchnię.
- `--headless -- --road-test`: streaming, szerokość oraz nachylenie rzeczywistych tras Silesii.
- `--headless -- --smoke-test`: uruchomienie całej gry, ruch, kolizje, kamery i glob.
- `-- --capture-road`: podgląd w `artifacts/highway.png`.
- `--headless --script res://tools/build_highways.gd`: ponowny eksport katalogu i trzech scen assetów.


## ??czniki i zjazdy

`highway_interchange.gd` ??czy oba pocz?tki autostrad ze wsp?ln? p?yt? w?z?a. ??czniki przejmuj? dok?adne przekroje i normalne istniej?cych nitek; profil pionowy jest liczony wed?ug d?ugo?ci ?uku. Maksymalne nachylenia aktualnych ??cznik?w wynosz? oko?o 4,09% i 3,63%.

Dwa zjazdy wybieraj? pobliskie miejsca l?dowania, uwzgl?dniaj?c koszt wyr?wnania gruntu i odst?p od innych jezdni. Ich spadki wynosz? obecnie oko?o 1,87% oraz 1,60%. Za ko?cem jezdni pozostaje 20 m wyr?wnanego wybiegu i kolejne 20 m przej?cia w naturalny teren. Wloty pozostaj? otwarte, a barierki ko?cz? si? przed przej?ciem w grunt. Ko?ce ramp dochodz? do terenu na ca?ej szeroko?ci. Teren pod rampami jest profilowany z ?agodnym przej?ciem na poboczach i wybiegiem za ko?cem nawierzchni; ska?y s? wy??czone z przejazd?w. Siatka gruntu przy rampach zachowuje rozdzielczo?? 2 m r?wnie? w dalszym LOD. Kolizje i wizualny teren korzystaj? z tego samego profilu.

`--headless --script res://tests/interchange_test.gd` sprawdza sp?jno?? przekroj?w, normalnych, ograniczenie nachylenia, oba zej?cia na grunt i rzeczywiste raycasty przez nawierzchni? oraz wloty. Przy pracy z ujemnymi wysoko?ciami poprawiono r?wnie? istniej?ce wyliczenie dolnej granicy kolizji lorry: odnosi si? teraz do wysoko?ci pojazdu, nie do globalnego poziomu zera.


Podgl?d niewidocznej p??kuli: `-- --capture-globe --farside`, wynik w `artifacts/globe_farside.png`. Trzy nowe trasy u?ywaj? najkr?tszych ?uk?w wielkiego ko?a, z oznaczeniem `connection_rule: farside_region` w katalogu. Nie zmienia to lokalnej geometrii Silesii ani ograniczenia obecnego ?wiata do jednego grywalnego sektora.


## Tycho: pojedynczy dojazd, bez węzła

Tycho nie ma autostrady strategicznej krótszej niż 700 km poza spurem do InPost Central (~22 km, `world_routes.json`). Wcześniejszy martwy stub `tycho-station-access` był drugim wlotem, przez co `highway_interchange.gd` budował węzeł na przechylonym terenie i łączniki osiągały ~19% nachylenia. Stub usunięty — Tycho ma jedną trasę, więc `highway_interchange.build()` kończy wcześnie (`mouths.size() < 2`) i węzła nie ma. Teren sektora jest zapieczony z prawdziwego `NAC_DTM_TYCHOPK` (2 m/px) do `godot/assets/sectors/tycho_station/` — patrz `docs/TERRAIN_ARCHITECTURE.md`. Spur InPostu zapieka się na tym terenie w granicy 6% (`_bake_route`).

## Lampy

?r?d?em jest dostarczony model `artifacts/sprites/lamp/Meshy_AI_Modern_Industrial_Str_0909190745_texture.glb`. `tools/prepare_highway_lamp.py` przygotowuje kopi? do gry: 3500 tr?jk?t?w, tekstury 1024? i wysoko?? 12 m. Orygina? pozostaje bez zmian; wynik znajduje si? w `godot/assets/roads/lamp`.

Lampy stoj? wzd?u? ca?ych lokalnych autostrad, obu ??cznik?w i obu zjazd?w, co 40 m po ka?dej stronie, z przesuni?ciem rz?d?w o 20 m. Cztery dodatkowe latarnie stoj? w naro?nikach w?z?a i kieruj? ?wiat?o ku jego ?rodkowi, pozostawiaj?c wloty wolne. ??cznie w aktualnym sektorze s? 182 lampy. S?upy stoj? na wspornikach poza szeroko?ci? pas?w, a ramiona kieruj? si? do ?rodka drogi. Rozstaw jest liczony po d?ugo?ci trasy i nie resetuje si? na granicach paneli ani kafli.

Bliskie lampy maj? ciep?e ?wiat?o kierowane w d??. Dalekie zachowuj? model i ?wiec?c? opraw? bez aktywnego reflektora; modele s? grupowane w MultiMesh i zwalniane razem z kaflami. ?wiat?a zanikaj? stopniowo wraz z odleg?o?ci?. Schemat o?wietlenia zapisano tak?e w katalogu sieci; fizyczne lampy s? tworzone tam, gdzie istnieje grywalna geometria drogi, a nie jako miliony obiekt?w na globie.

Test: `--headless --script res://tests/highway_lamps_test.gd`. Podgl?d przy przygaszonym ?wietle s?onecznym: `-- --capture-road --lamps`, wynik `artifacts/highway_lights.png`. Tryb podgl?du nie zmienia o?wietlenia zwyk?ej rozgrywki.
