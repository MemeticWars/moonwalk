# Autostrady między lokacjami

Sieć świata powstaje z lokacji w `godot/assets/moon/colonies.json`; `godot/scripts/highway_network.gd` wybiera połączenia i tworzy kanoniczną linię środkową całej trasy co najwyżej co 10 km, a `godot/scripts/road_streamer.gd` buduje fragmenty potrzebne w aktywnym sektorze. Dane tras do wizualizacji globu są w `godot/assets/roads/world_routes.json`.

Jezdnia ma szerokość równą dwóm szerokościom łazika, obecnie około 6 m, z poboczami po 0,4 m i lampami po obu stronach co około 40 m. Generator ogranicza lokalny spadek do 6%, rezerwuje teren pod drogę i stosuje pełną kolizję blisko gracza oraz uproszczony LOD dalej.

Poza sektorem z pełną kolizją `road_streamer.gd` buduje widoczny daleki LOD każdej trasy do 20 km od aktywnej kolonii. Ten pomost jest uproszczony, bez lamp, barierek i kolizji, ale zachowuje szerokość jezdni i łączy się z lokalną autostradą.

W Tycho główna jezdnia zaczyna się 150 m od lokalnego początku trasy, poza śluzą kopuły. Osobna droga dojazdowa z bramy i zjazd kosmodromu dochodzą do wspólnego otwarcia na stacji 175 m; na długości 110 m wokół niego nie ma barierek ani lamp blokujących przejazd.

Rozwój ogromnych autostrad powinien zachować podział na: globalny graf tras, segmenty wyznaczane geodezyjnie oraz lokalne paczki streamowane przy sektorze. Nie należy tworzyć jednej sceny 3D dla setek kilometrów; po przejściu do nowej lokacji trzeba zwolnić poprzedni sektor i odtworzyć lokalne odcinki przy nowym początku układu.

Testy: `godot/tests/highway_test.gd`, `godot/tests/interchange_test.gd`, `godot/tests/highway_lamps_test.gd` oraz opcja gry `--road-test`. Starszy opis implementacji pozostaje w `docs/HIGHWAYS.md`.
