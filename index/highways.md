# Autostrady między lokacjami

Sieć świata powstaje z lokacji w `godot/assets/moon/colonies.json`; `godot/scripts/highway_network.gd` wybiera połączenia, a `godot/scripts/road_streamer.gd` buduje jedynie fragmenty potrzebne w aktywnym sektorze. Dane tras do wizualizacji globu są w `godot/assets/roads/world_routes.json`.

Jezdnia ma szerokość równą dwóm szerokościom łazika, obecnie około 6 m, z poboczami po 0,4 m i lampami po obu stronach co około 40 m. Generator ogranicza lokalny spadek do 6%, rezerwuje teren pod drogę i stosuje pełną kolizję blisko gracza oraz uproszczony LOD dalej.

Rozwój ogromnych autostrad powinien zachować podział na: globalny graf tras, segmenty wyznaczane geodezyjnie oraz lokalne paczki streamowane przy sektorze. Nie należy tworzyć jednej sceny 3D dla setek kilometrów; po przejściu do nowej lokacji trzeba zwolnić poprzedni sektor i odtworzyć lokalne odcinki przy nowym początku układu.

Testy: `godot/tests/highway_test.gd`, `godot/tests/interchange_test.gd`, `godot/tests/highway_lamps_test.gd` oraz opcja gry `--road-test`. Starszy opis implementacji pozostaje w `docs/HIGHWAYS.md`.
