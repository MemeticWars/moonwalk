# Ciągłość terenu i deterministyczna geometria

Wysokość terenu wynika ze współrzędnych świata, danych DEM i zarejestrowanych wyrównań pod zabudowę oraz drogi. Kolejność ładowania kafli nie może zmieniać geometrii przy tym samym zestawie danych i poziomów LOD; gotowe kafle należy przebudować po zmianie wyrównań, zamiast pozostawiać starą powierzchnię obok nowej.

## Tycho: poprawka granic siatek

Lokalne kafle 64 m mają wspólną siatkę co 2 m także w dalszym pierścieniu. Dalszy pierścień nadal pomija kolizje i skały; zwiększa to liczbę jego trójkątów, ale usuwa niedopasowanie brzegów 2 m/8 m bez zmiany wysokości gruntu pod postacią.

`godot/scripts/lunar_horizon.gd` dzieli teren nad całym lokalnym obszarem oraz dodatkowym pasem 64 m na kafle minimalne, które można jednoznacznie wyłączyć po pojawieniu się lokalnej powierzchni. Na granicach dalszych poziomów LOD pośrednie wierzchołki drobniejszej krawędzi leżą na odcinku krawędzi większego sąsiada; normalne mają ten sam sposób próbkowania i interpolacji. Zmiana sąsiadów wymusza przebudowanie brzegu, a zastępowane siatki są wymieniane razem, aby rodzic i jego dzieci nie były równocześnie widoczne.

`add_city_pad()` w `godot/scripts/lunar_terrain.gd` grupuje wyrównania z jednej klatki i odświeża istniejący teren oraz jego kolizje. Jest to konieczne przy śluzie i aneksach Tycho, ponieważ pierwsze kafle powstają przed rejestracją tych wyrównań.

## Weryfikacja

Uruchamiaj bez okna, z zapisywalnym `--log-file`, przez lokalny silnik Godota:

- `--headless --path godot --script res://tests/terrain_transition_test.gd`: ciągłość granic obszaru DEM, wysokości kolizji, pokrycie i limit cache.
- `--headless --path godot --script res://tests/terrain_seams_test.gd`: wspólne krawędzie 2 m, brak dużego liścia horyzontu nad lokalnymi kaflami, dopasowanie do odcinka grubszego LOD, identyczne siatki po odwróceniu kolejności planowania oraz aktualizacja kafli po dodaniu wyrównania.

Testy geometryczne nie zastępują oceny obrazu w grze. Nie zmieniono źródłowych plików DEM ani nie zapieczono nowych arkuszy; poprawka dotyczy deterministycznego budowania siatek z istniejących danych.
