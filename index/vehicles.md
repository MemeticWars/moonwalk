# Lorry Agnes i konwój transportowy

Lorry czeka na kierowcę w istniejącej lokalizacji łazika. Podejdź na mniej niż 8 m i naciśnij **F**, aby wsiąść; ponowne **F** pozwala wysiąść po zatrzymaniu, jeśli obok znajduje się dostatecznie płaski, wolny grunt. W kabinie Agnes ma wyłączone sterowanie piesze i kolizję, a kamera śledzi łazik z kontrolą przeszkód.

Sterowanie: **W** napęd do przodu, **S** hamowanie przed przejściem na wsteczny, **A/D** skręt, **Spacja** hamulec, **L** światła, **Esc** pauza całego konwoju. Prędkości graniczne napędu wynoszą 8 m/s do przodu i 2,5 m/s wstecz; spadek może dodatkowo rozpędzać pojazd i wymaga hamowania. Puszczenie gazu pozostawia pęd, a wyjście z kabiny włącza hamulec postojowy.

## Fizyka

`godot/scripts/lunar_lorry.gd` zachowuje VehicleBody3D i cztery rzeczywiste zawieszenia VehicleWheel3D. Projekt używa przyspieszenia 1,62 m/s²; masa pojazdu pozostaje 2600 kg, bo mniejsza grawitacja zmniejsza ciężar, a nie bezwładność. W trybie kierowania usunięto liniowe tłumienie imitujące opór powietrza i automatyczne prostowanie nadwozia; opór toczenia działa wyłącznie przy kontakcie kół. Siła napędu i hamowania zależy od kontaktu kół i przyczepności, skręt jest ograniczany wraz ze wzrostem prędkości, a ślady powstają tylko przy kontakcie z gruntem.

To przybliżenie do gry, bez deformowalnego regolitu i pełnego modelu zapadania kół. Parametry przyczepności oraz zawieszenia są doborem projektowym, nie wynikiem pomiarów tego fikcyjnego pojazdu. Odniesienia: [NASA: grawitacja Księżyca](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/moon/), [Godot: VehicleBody3D i jego ograniczenia](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html).

## Ciężarówki-drony

`godot/scripts/lunar_truck.gd` wykorzystuje dostarczony `godot/assets/track/lunar_support_rover_lod.glb`, normalizowany do 6 m długości. Każdy dron ma osiem fizycznych kół, kolizję kadłuba i masę 3600 kg; napęd współdzieli z Lorry. Import Godota zmienia nazwy części `track_wheel_00` na `track_00` i analogicznie dla pozostałych siedmiu kół.

`godot/scripts/rover_convoy.gd` dodaje dwa drony za Lorry, zapisuje przebytą trasę poprzednika co 2 m i prowadzi po niej następny pojazd. Dystans bezpieczeństwa uwzględnia prędkość i drogę hamowania; drony zatrzymują się przed wykrytą przeszkodą oraz przy cofaniu poprzednika. Nie mają jeszcze planowania objazdów — przy zablokowanym przejeździe wymagają interwencji kierowcy. Lider zatrzymuje się przy oddaleniu drona ponad 85 m, aby konwój pozostał w obszarze z kolizjami terenu; historia drogi ma limit 2048 punktów.

Integracja w `moonwalk.gd` tworzy konwój po dodaniu Agnes w sektorach, w których istnieje Lorry. Podczas jazdy streaming terenu podąża za łazikiem; w pauzie i na mapie pojazdy są zamrożone. Istniejący `--lorry-test` zachowuje osobny patrol diagnostyczny i nie tworzy sterowania kierowcy.

## Testy

Uruchamiaj lokalnego Godota z `--headless --path godot --log-file <zapisywalny_plik>` oraz:

- `--script res://tests/rover_drive_test.gd`: oba modele i liczby kół, kierunek napędu, toczenie po puszczeniu gazu, hamulec, podążanie drona po zakręcie i lot w grawitacji księżycowej.
- `--script res://tests/convoy_game_test.gd -- --agent-run`: integracja pełnej sceny Tycho, dwa drony, wsiadanie, śledzenie pozycji kierowcy, pauza, odmowa wysiadania w ruchu i wyjście po zatrzymaniu.
