# Stawy i potok Tycho

Źródłem wspólnych wymiarów jest `godot/scripts/tycho_water_layout.gd`, bez zależności od scen: mały staw w parku D1 ma nieckę głęboką na 1 m, a duży staw w zachodniej sferze m3 na 1,5 m. Duży staw został przeniesiony z m2 do m3; głębokości są mierzone od poziomu otaczającego gruntu, a lustro wody leży 12,5 cm niżej (obniżone o dodatkowe 10 cm). Wspólna stała `WATER_LEVEL_OFFSET` w `tycho_water_feature.gd` steruje poziomem obu stawów i potoku; pozycje ryb są względem niej przesunięte, żeby pozostawały pod wodą. Promienie stawów pozostają odpowiednio 4,5×3,2 m i 32×18 m.

Potok ma 0,50 m szerokości przy brzegu i 0,50 m głębokości, z przekrojem U opisanym dolną połową elipsy. Z parku biegnie na zachód, przy alei poprzecznej, przez przerwę między twin-houses na z=0 i z=-22, między zbiornikami na z=-4 i z=-16, następnie do zachodniego przejścia D1–m3. Współrzędne te są lokalne względem `TychoSite.CENTER`; trasa dochodzi wewnątrz obu niecek, a narożniki są zaokrąglone krzywymi kwadratowymi, które nie wychodzą poza wielokąt punktów kontrolnych.

Alejkę serwisową na x=-30, z=-11 przecina mostek z własną kolizją. W tunelu D1–m3 potok biegnie przy jednej ścianie, na z=+2,5 m względem osi przejścia, a obok znajduje się uliczka szerokości 2,4 m, ze środkiem na z=+0,8 m i oznaczoną krawędzią od strony wody. Uliczka ma kolizję i długość 41 m (x=-135 do -94), więc obejmuje także dojścia po obu stronach tunelu; generuje ją `tycho_east_annex.gd:_build_west_walkway()`. Przejście między kopułami wraz z brzegami jest wyrównane do wspólnego `city_level`, żeby blend dwóch padów nie zostawiał grzbietu DEM blokującego wodę. Duży staw leży w pustej sferze m3, w promieniu jej istniejącego płaskiego pada.

`lunar_terrain.gd` odejmuje profil niecek po wyrównaniu zabudowy i dróg, przy każdym deterministycznym generowaniu kafla. Siatka jest zagęszczona do 6,25 cm w komórkach przy potoku i 50 cm przy stawach; poza nimi zostaje siatka 2 m. Krawędzie drobniejszych komórek są interpolowane do sąsiednich grubszych krawędzi, a `height_at()` i kolizja używają tych samych wierzchołków oraz przekątnej trójkątów. Pionowe maskujące pasy kafli są pomijane przy wykopie, by nie tworzyć przegród w korycie.

`tycho_city.gd` dopasowuje siatkę trawnika do niecki i zostawia pas bez źdźbeł wzdłuż zaokrąglonej trasy. `tycho_water_feature.gd` tworzy osobne, poziome powierzchnie wody z istniejącym shaderem widocznym z efektem obrysu. Ryby pływają tylko w stawach, poniżej lustra; poprzedni ruch po wydłużonych elipsach nie mieścił się w nowym, wąskim korycie.

## Kolor, fale i kształt powierzchni (2026-09-13)

Poprzedni przygaszony szarozielony materiał (uzasadniany tym, że czysta woda
ma i tak własny delikatny niebieski odcień, więc czarne niebo nie musi dawać
czarnej wody) na żywo pod czarnym niebem kopuły wyglądał po prostu na czarny,
nie niebieskawy — zmieniony na wyraźny gradient głębi po zgłoszeniu przez
użytkownika. `color_deep`/`color_shallow` w `water.gdshader` nie czytają już
tekstury głębi (ten odczyt jest i pozostaje zablokowany, patrz niżej) — są
teraz mieszane wagą zapisaną w kolorze wierzchołka (`COLOR.r`, 1.0 = środek
stawu, 0.0 = brzeg stawu i cały, jednostajnie płytki potok), nadawaną w
`tycho_water_feature.gd::_add_pond()/_add_stream()`. `albedo_fresnel` (kolor
pod kątem stycznym, czyli to, co czyta się jako "niebo odbite w wodzie")
rozjaśniony z prawie czarnego na jasny niebieskoszary, a `roughness`
podniesiony (0.10→0.30), żeby zamiast ostrego czarnego lustra nieba było
miękkie, jasne połyskiwanie.

Powierzchnia stawu (`_add_pond`) nie jest już pojedynczym wachlarzem
trójkątów od jednego wspólnego wierzchołka środkowego do obwodu — przy takiej
siatce przesunięcie fal w vertex shaderze poruszało tym jednym środkowym
wierzchołkiem względem obwodu i dawało płasko cieniowane, trójkątne "języki"
wody rozchodzące się od środka, z postrzępionym (nie gładko owalnym)
brzegiem. Teraz to 6 współśrodkowych pierścieni (nadal elipsa `radii.x/y`,
kształt owalny nie zmienił się, po prostu wcześniej fale go maskowały).
`WaveSteepnesses`/`WaveAmplitudes` w `tycho_water_feature.gd::_make_water_material()`
zmniejszone ~6x — poprzednie 0,25 m bezpośredniego przesunięcia pionowego
(patrz `P_DEG()` w shaderze: `result.y = Steepness * sin(...)`) było
nieproporcjonalne do stawu o promieniu 3-4,5 m.

Odczyt tekstury głębi/ekranu (REFRACTION/DEPTH_FOG/SHORE_FOAM w
`water.gdshader`) pozostaje **celowo wyłączony** — patrz komentarz na
początku pliku shadera: dowolny materiał deklarujący `hint_screen_texture`/
`hint_depth_texture` jest wymazywany przez efekt obrysu (K), więc prawdziwa
przezroczystość alpha/refrakcja nie jest tu dostępna bez ponownego złamania
obrysu. Przejrzystość jest dlatego realizowana metodą screen-door w
nieprzezroczystym przebiegu: stabilny wzór odrzuca 44% próbek płytkiej wody
i 20% próbek nad głębią, naprawdę odsłaniając dno i ryby między zachowanymi
próbkami z falami i refleksami. Brzeg i cały płytki potok są dodatkowo
jaśniejsze (`color_shallow`), a środek stawu zachowuje głębszy błękit.

Ryby korzystają z `pond_fish.gdshader`, ponieważ źródłowy GLB jest jedną
siatką bez szkieletu i klipów. Shader prowadzi falę wzdłuż ciała i zwiększa
jej amplitudę na ogonie, natomiast `pond_fish.gd` dodaje niezależne fazy,
kołysanie, pochylenie na zakrętach, bobbing oraz krótkie przyspieszenie po
wybraniu nowego celu. Model jest też ustawiany głową (lokalne `-X`) zgodnie
z rzeczywistym kierunkiem ruchu.

Podgląd bez pełnej nawigacji: `--capture-water --agent-run` (flaga w
`moonwalk.gd::_capture_water()`, wzorowana na `--capture-fox`) łapie staw D1
z poziomu oczu, tak jak zobaczy go Agnes idąc obok.

Test: `Godot --headless --path godot --log-file <plik> --script res://tests/tycho_water_test.gd -- --real-dem`. Obejmuje głębokości, przekrój U, prześwity względem rzeczywistych wymiarów modułów, łagodne zakręty, zgodność raycastu kolizji z `height_at()`, obniżony trawnik, orientację powierzchni wody, osobną uliczkę z kolizją przez tunel i brak grzbietu na rzeczywistym DEM Tycho. Przed uruchomieniem stosuj rejestr aktywnej pracy i zasady z `index/collaboration.md`.
