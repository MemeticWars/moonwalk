# Lorry Agnes i konwój transportowy

Lorry czeka na kierowcę w istniejącej lokalizacji łazika. Podejdź na mniej niż 8 m i naciśnij **E**, aby wsiąść; ponowne **E** pozwala wysiąść po zatrzymaniu, jeśli obok znajduje się dostatecznie płaski, wolny grunt. W kabinie Agnes ma wyłączone sterowanie piesze i kolizję, a kamera śledzi łazik z kontrolą przeszkód.

Sterowanie: **W** napęd do przodu, **S** hamowanie przed przejściem na wsteczny, **A/D** skręt, **Spacja** hamulec, **E** wysiadanie, **L** światła, **Esc** pauza całego konwoju. Prędkości graniczne napędu wynoszą 8 m/s do przodu i 2,5 m/s wstecz; spadek może dodatkowo rozpędzać pojazd i wymaga hamowania. Puszczenie gazu pozostawia pęd, a wyjście z kabiny włącza hamulec postojowy.

## Fizyka

`godot/scripts/lunar_lorry.gd` zachowuje VehicleBody3D i cztery rzeczywiste zawieszenia VehicleWheel3D. Projekt używa przyspieszenia 1,62 m/s²; masa pojazdu pozostaje 2600 kg, bo mniejsza grawitacja zmniejsza ciężar, a nie bezwładność. W trybie kierowania usunięto liniowe tłumienie imitujące opór powietrza i automatyczne prostowanie nadwozia; opór toczenia działa wyłącznie przy kontakcie kół. Siła napędu i hamowania zależy od kontaktu kół i przyczepności, skręt jest ograniczany wraz ze wzrostem prędkości, a ślady powstają tylko przy kontakcie z gruntem.

To przybliżenie do gry, bez deformowalnego regolitu i pełnego modelu zapadania kół. Parametry przyczepności oraz zawieszenia są doborem projektowym, nie wynikiem pomiarów tego fikcyjnego pojazdu. Odniesienia: [NASA: grawitacja Księżyca](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/moon/), [Godot: VehicleBody3D i jego ograniczenia](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html).

## Ciężarówki-drony

`godot/scripts/lunar_truck.gd` wykorzystuje teksturowany `godot/assets/lorry/lunar_logistics_rover_full.glb`, normalizowany do 12 m długości, czyli dwukrotnie większej skali liniowej niż pierwotny 6 m pojazd. Każdy dron ma osiem fizycznych kół (`wheel_0`..`wheel_7`), kolizję kadłuba i masę 28 800 kg, odzwierciedlającą ośmiokrotnie większą objętość; napęd współdzieli z Lorry.

Przed wjazdem przez śluzę Tycho `tycho_cosmoport.gd` buduje równy parking z dwoma oznaczonymi stanowiskami 16×28 m, oświetleniem i kolizją. Jest on z boku drogi dojazdowej, po zewnętrznej stronie portalu i przed początkiem autostrady; `add_city_pad()` wyrównuje pod nim teren przed zbudowaniem nawierzchni. Drony rozpoczynają tam pracę, a nie w osi śluzy.

`godot/scripts/rover_convoy.gd` dodaje dwa drony za Lorry, zapisuje przebytą trasę poprzednika co 2 m i prowadzi po niej następny pojazd. Dystans bezpieczeństwa uwzględnia prędkość, drogę hamowania oraz długość dużego pojazdu; drony zatrzymują się przed wykrytą przeszkodą oraz przy cofaniu poprzednika. Nie mają jeszcze planowania objazdów — przy zablokowanym przejeździe wymagają interwencji kierowcy. Lider zatrzymuje się przy oddaleniu drona ponad 85 m, aby konwój pozostał w obszarze z kolizjami terenu; historia drogi ma limit 2048 punktów.

Integracja w `moonwalk.gd` tworzy konwój po dodaniu Agnes w sektorach, w których istnieje Lorry. Podczas jazdy streaming terenu podąża za łazikiem; w pauzie i na mapie pojazdy są zamrożone. Istniejący `--lorry-test` zachowuje osobny patrol diagnostyczny i nie tworzy sterowania kierowcy.

## Materiał i geometria ciężarówek

`godot/assets/lorry/lunar_logistics_rover_full.glb` łączy geometrię z dwóch osobnych eksportów Meshy tego samego łazika, sklejonych skryptem `tools/prepare_lunar_truck.py` (uruchamiany przez `blender --background --python tools/prepare_lunar_truck.py`):

- kadłub: pojedyncza, w pełni teksturowana siatka z `artifacts/sprites/track/Meshy_AI_Lunar_Logistics_Rover_0908201853_texture.glb` (3 osadzone obrazy JPEG 2048×2048, zgodne UV) — jej własne wybrzuszenia kół są zespolone z nadwoziem (nawet po spawaniu wierzchołków to jedna spójna siatka), więc zostają bez zmian;
- koła: 8 osobnych siatek z `artifacts/sprites/track/Meshy_AI_Lunar Logistics Rover_1788897764_part-segmentation.glb` (part-segmentation, bez tekstur — dwie pozostałe części tego pliku to jego własny kadłub/góra, odrzucane, bo kadłub bierzemy z pliku teksturowanego). Obie eksportacje przedstawiają ten sam pojazd w spójnie różnej skali (~15,77× na każdej z trzech osi niezależnie, zweryfikowane przed napisaniem skryptu), więc jeden jednorodny współczynnik przenosi koła do układu kadłuba bez zniekształcenia tarczy koła; wyrównanie w pionie łączy płaszczyzny styku z gruntem obu modeli (nie wspólny początek układu — początek dawcy leży w płaszczyźnie kół, środek kadłuba leży w jego środku objętości). Koła dostają płaski, ciemny materiał gumy zamiast szarego placeholdera part-segmentation.

Nie należy rozdzielać obrazów z pliku teksturowego ani przypisywać ich ręcznie do siatki kół z part-segmentation — to dwie różne generacje Meshy o innej topologii, bez wspólnych UV.

## Testy

Uruchamiaj lokalnego Godota z `--headless --path godot --log-file <zapisywalny_plik>` oraz:

- `--script res://tests/rover_drive_test.gd`: oba modele i liczby kół, kierunek napędu, toczenie po puszczeniu gazu, hamulec, podążanie drona po zakręcie i lot w grawitacji księżycowej.
- `--script res://tests/convoy_game_test.gd -- --agent-run`: integracja pełnej sceny Tycho, dwa drony, wsiadanie, śledzenie pozycji kierowcy, pauza, odmowa wysiadania w ruchu i wyjście po zatrzymaniu.
- `--script res://tests/tycho_truck_parking_test.gd`: wyrównany parking po zewnętrznej stronie śluzy, dwa stanowiska, kolizja i dwukrotnie większy model ciężarówki.
