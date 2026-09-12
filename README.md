# Moonwalk — pierwszy grywalny sektor

**Autostrady:** nowe proceduralne pomosty betonowe z barierkami, wsp?lnymi kraw?dziami paneli i kolizj? nawierzchni. Jezdnia ~6,0 m (2 ? szeroko?? ?azika ~3,0 m), o?wietlona dostarczonymi latarniami co 40 m po obu stronach. Glob pokazuje 12 po??cze?: 9 poni?ej 700 km oraz 3 dodatkowe mi?dzy koloniami niewidocznej p??kuli; lokalnie dost?pne s? pocz?tkowe odcinki w sektorze Silesii. [Zasady, assety i testy](docs/HIGHWAYS.md), [podgl?d](artifacts/highway.png).

Projekt Godot 4.6.1: Agnes w kombinezonie porusza się po powierzchni Księżyca, korzystając ze sterowania Thei z Elvenpass. Jest chód, bieg, mała grawitacja, skok, pięć kamer Elvenpass, klasyczne sterowanie WASD, autopilot, ślady, skały z kolizjami, punkt terenowy InPost oraz glob z mapami NASA. Teren powstaje w kaflach wokół postaci.

**Styl renderowania:** renderer **Forward+**. Pełnoekranowy shader dorysowuje czarną kreskę na geometrycznych krawędziach (bufor głębi + normalnych), bez zmiany modeli, materiałów ani świateł. Dwa style do wyboru: **Komiks** (`shaders/comic_outline.gdshader`, domyślny) i **Moebius / ligne claire** (`shaders/moebius_outline.gdshader`, cieńsza kreska, mocniejsze kontury sylwetki niż linie wewnętrzne). Cykl klawiszem **K** (Wyłączona → Komiks → Moebius) lub z listy „Styl kreski" w menu pauzy. Parametry (`line_width`, czułości, `far_fade_m`) w materiale kwadu pod kamerą.

**Styl malarski:** niezależny drugi post-process (`shaders/painterly_post.gdshader`, `canvas_item` na `CanvasLayer` 0 — nad widokiem 3D z kreską, pod HUD-em). Cykl klawiszem **B** lub listą „Styl malarski" w menu pauzy: **Realistyczny** (wyłączony), **Pastelowy**, **Akwarela**, **Farba olejna** (Kuwahara — najdroższy; przy spadkach FPS zmniejsz `const int R` z 3 na 2) i **Tusz + akwarela** (akwarelowe plamy + czarna kreska z Sobela na ostrym obrazie, jedyny tryb, w którym kreska zostaje ostra mimo rozmycia). Łączenie: **K-kreska + B-akwarela** rozmywa też kreskę; do ostrego tuszu na miękkim kolorze użyj samego trybu 4 (K wyłączone). Podglądy: `artifacts/painterly_{0..4}_*.png`.

**Nagrywanie wideo:** przycisk „Nagrywanie wideo" w menu pauzy lub klawisz **I**. Ponieważ `MovieWriter` Godota da się uzbroić tylko przy starcie silnika, nagrywanie uruchamia grę w drugim procesie z `--write-movie` (tryb Movie Maker), przenosząc bieżącą pozycję gracza (`--rec-at`). W trakcie nagrywania miga „● REC", a gra działa w zwolnionym tempie (stały krok czasowy) — gotowy plik `.avi` (MJPEG, 60 fps) trafia do `artifacts/moonwalk_<data>.avi`. Ponowne **I** (lub przycisk „Zakończ nagrywanie") kończy i zapisuje film.

**Uruchomienie:** kliknij `START.cmd` lub wykonaj `powershell -ExecutionPolicy Bypass -File .\START.ps1`. Edytor: skrypt z `-Editor`. Można też otworzyć `godot/project.godot` w Godocie i nacisnąć F5 (scena główna: `scenes/moonwalk.tscn`). Lokalna kopia silnika znajduje się w `tools/godot`.

| Klasyczne sterowanie (domyślne) | Działanie |
|---|---|
| WASD | Ruch względem kamery; jednakowa szybkość po przekątnej |
| Shift + ruch | Bieg 5,2 m/s; sam Shift nie porusza postaci |
| Spacja | Skok; w swobodnej kamerze lot w górę |
| H | Agnes: płynne złote przyciemnienie szybki (od góry i od skroni) |
| Ctrl | Lot w dół w swobodnej kamerze |
| Mysz | Rozglądanie góra/dół i na boki |
| Rolka | Przybliżenie kamery orbitalnej co 0,7 m, zakres 2,2–12 m |
| C | Widok zza pleców / pierwsza osoba |
| V | Swobodna kamera / powrót do poprzedniej kamery |
| P / Num Lock | Autopilot w aktualnym kierunku; Shift+P włącza automatyczny bieg |
| Esc | Pauza, profil sterowania, pięć kamer i czułość myszy |
| M | Glob; LPM + przeciągnięcie obraca glob |
| Tab | Wizualizacja pokrycia: łagodny regolit / stoki |
| F8 | Powrót do miejsca startu |

Domyślny widok to kamera zza pleców. W TPP postać płynnie obraca się w kierunku ruchu. W FPP A/D przesuwa na boki, a wysokość oczu wynosi 1,55 m. Kamera swobodna używa WASD + Spacja/Ctrl; Shift przyspiesza lot. Profil, ostatnia kamera i czułość są zapisywane w `user://controls.cfg`.

**Wszystkie kamery Elvenpass pozostają dostępne:** żabia, normalna, z lotu ptaka, pierwsza osoba i swobodna. Wybór wszystkich presetów jest w pauzie. Profil „Elvenpass” zachowuje W/S przód/tył, animowane obroty A/D o 20°, Q bieg, LPM/C cykl pięciu kamer, PPM/Esc pauzę i R powrót. V oraz P/Num Lock działają w obu profilach.

**Autopilot i eksploracja:** włącz P podczas marszu (lub Shift+P dla biegu w profilu klasycznym), a następnie V, aby niezależnie latać kamerą. Mysz i WASD w swobodnej kamerze nie zmieniają trasy postaci. Ponowne P zatrzymuje autopilota; w zwykłych kamerach świeże naciśnięcie WASD przejmuje sterowanie ręczne. Pauza zatrzymuje również autopilota. Jest to marsz/bieg w ustalonym kierunku, nie nawigacja do celu: korzysta z kolizji, a po sekundzie blokady zatrzymuje się. Nie omija samodzielnie przeszkód. Teren nadal streamuje wokół poruszającej się postaci.

## Skład projektu: kod (GitHub) + assety (Google Drive)

Repozytorium git ([MemeticWars/moonwalk](https://github.com/MemeticWars/moonwalk)) trzyma tylko kod: skrypty GDScript, sceny `.tscn`, shadery, dokumentację i skrypty narzędziowe (`tools/*.py`, `tools/*.mjs`). Ciężkie binarne assety **nie są** w gicie (patrz `.gitignore`) — leżą w udostępnionym folderze Google Drive i trzeba je dograć ręcznie do odpowiednich ścieżek po sklonowaniu repo.

**Co jest wyłączone z gita i ile waży:**

| Ścieżka | Zawartość | Waga |
|---|---|---|
| `godot/assets/` | modele `.glb`, tekstury, kafle wysokości `.bin` (Agnes, Theia, lorry, moduły kolonii, teren mezo/regolit) — **faktycznie ładowane przez `res://` w scenach/skryptach** | ~2,1 GB |
| `source_data/` | surowe wejście dla `tools/bake_sector_dtm.mjs`: GeoTIFF-y LOLA/LROC globalne (`ldem_64_uint.tif`, `ldem_4_uint.tif`, `lroc_color_poles_4k.tif`) oraz `dem_real/` — NAC DTM Tycho (2 m/px) i LOLA biegun południowy (5 m/px), nigdy nie wczytywane bezpośrednio przez grę, tylko przez narzędzie do bakowania sektorów | ~5,2 GB |
| `artifacts/sprites/` | wyrenderowane podglądy/screenshoty odsyłaczy z tego README | ~1,3 GB |
| `tools/SunshineClouds2-main.zip`, `tools/SunshineClouds2-source/` | oryginalne archiwum addona chmur (już wypakowane i używane z `godot/addons/SunshineClouds2/`, więc to tylko zbędna kopia źródła) | ~27 MB |

Razem ~8,6 GB. Silnik (`tools/godot/Godot_v4.6.1-stable_win64*.exe`, ~270 MB + `tools/godot.zip`) też jest poza gitem, ale nie trzeba go trzymać na Drive — to zwykła dystrybucja Godota, do pobrania ze [strony Godota](https://godotengine.org/download) w wersji **4.6.1**.

**Jak złożyć projekt od zera:**
1. `git clone git@github.com:MemeticWars/moonwalk.git`
2. Z folderu Google Drive skopiuj `godot/assets/`, `source_data/` i (opcjonalnie, tylko dla działających linków w tym README) `artifacts/sprites/` do tych samych ścieżek w klonie repo.
3. Kafle terenu (`godot/assets/sectors/*` i `godot/assets/moon/meso/`) to po kilka tysięcy plików po kilka KB każdy — zamiast nich na Drive leżą archiwa `godot/assets/sectors/{tycho_station,lubin_deep,shackleton_ice}.zip` i `godot/assets/moon/meso.zip`. Rozpakuj każde do folderu o tej samej nazwie co archiwum (np. `tycho_station.zip` → `godot/assets/sectors/tycho_station/`, `meso.zip` → `godot/assets/moon/meso/`).
4. Pobierz Godota 4.6.1 (Forward+, `win64`) i wypakuj/skopiuj do `tools/godot/`, albo wskaż własną instalację silnika.
5. `START.cmd` (Agnes) lub `powershell -ExecutionPolicy Bypass -File .\START.ps1 -Editor` żeby otworzyć edytor na `godot/project.godot`.

Bez kroku 2 projekt się otworzy i skrypty się skompilują, ale sceny będą pokazywać brakujące zasoby (modele/tekstury) tam, gdzie odwołują się do `res://assets/...`.

## Co jest gotowe, a co jest szkicem

- **Proporcje i sztywny plecak Agnes:** głowa pomniejszona o 10% z płynnym przejściem wag przy szyi; hełm zmniejszono o kolejne 10% wokół mocowania głowy, a kopułę szybki pogłębiono do przodu, żeby twarz nie dotykała szkła. Plecak wydzielono z siatki kombinezonu jako `RigidBackpack`, bez skórowania i wag kości, mocowany jednym uchwytem do Spine02. Obraca się z tułowiem, ale nie zgina się wraz z kręgosłupem. Pasy pozostają na kombinezonie. Przygotowane kopie sześciu animacji znajdują się w `godot/assets/agnes/fitted`; odtwarza je `tools/fit_agnes.py` uruchomiony po `tools/prepare_agnes.py`. Oryginały pozostają bez zmian. [Plecak od tyłu](artifacts/backpack_0_back.png), [plecak podczas skoku](artifacts/backpack_5_side.png).
- **Chód:** kości obu ud w Spear Walk są odsunięte o 3 cm na stronę, a obie stopy o 1,5 cm na stronę. Minimalny odstęp butów w cyklu wynosi 17 cm, więc nie nachodzą na siebie. Ślady nie używają już stałego offsetu od środka postaci: są stawiane pod niższą stopą aktywnej animacji i wyrównywane do terenu. [Podgląd szerokiego chodu](artifacts/agnes_walk_wide_legs.png).
- **Zaokrąglone dachy:** wspinanie uruchamiane Q korzysta z `Crawl_and_Look_Back`, gdy dach nie daje stabilnego podparcia do wstawania. Sprawdzane jest pięć punktów wokół postaci, nachylenie do około 20° i różnica wysokości do 18 cm. Pełzanie śledzi powierzchnię małymi krokami; brak dalszego podparcia zatrzymuje ruch, a Q go przerywa. Po wejściu dokładna siatka dachu podtrzymuje zwykły chód. Kopię animacji przygotowują `tools/prepare_agnes.py` i `tools/fit_agnes.py`. Test: `--headless --script res://tests/crawl_roof_test.gd`; pełna wspinaczka na budynku: `--headless -- --climb-test`.

- **Hełm Agnes:** dopasowany `helmet.glb`, przywiązany do kości Head we wszystkich sześciu animacjach. W `helmet_fitted.glb` wycięto dolną część i usunięto wewnętrzne trójkąty zajmujące miejsce głowy. Dodatkowe przycięcie wyściółki zachowuje pierwszeństwo siatki Agnes: jej głowa, szyja i elementy kołnierza pozostają nienaruszone. Oryginał hełmu pozostaje bez zmian. Przód zamyka wypukła szybka. **H** płynnie wprowadza złote przyciemnienie: nieprzezroczystość rośnie od góry kopuły i od obu skroni ku czystemu oknu nad dolną częścią twarzy, a wartość jest wygładzana w czasie (`VISOR_SHADE_FADE`), więc naciśnięcie klawisza przenika stopniowo, nie skokowo. W FPP ten sam parametr steruje delikatnym złotym cieniem schodzącym z góry i z boków ekranu — środek widoku i HUD zostają czytelne. [Szkło](artifacts/helmet_clear.png), [złote przyciemnienie](artifacts/helmet_shaded.png). Odtwarzanie zasobów: `tools/prepare_agnes.py`, następnie `tools/cut_helmet.py`.

- Domyślna postać: **Agnes w kombinezonie**, z sześcioma plikami `*suit*.glb` z `artifacts/sprites/agnes`: Spear Walk, Running, Idle Turn Left, Idle Turn Right, Idle 5 oraz Jump Over Obstacle 2. Wspólny kontroler zapewnia te same kamery, WASD/Shift, profil Elvenpass z Q i obrotami A/D oraz niezależny autopilot. Podczas postoju działa Idle 5; pauza zatrzymuje animacje. [Postój](artifacts/agnes_idle.png), [bieg](artifacts/agnes_run.png).
- **Spacja: animowany skok Agnes.** Klip Jump Over Obstacle 2 (0,93 s) dopasowano do księżycowego lotu (około 3,2 s przy powrocie na tę samą wysokość). Faza pozy zależy od pionowej prędkości, a lądowanie od kontaktu z podłożem; końcówka lądowania trwa 0,25 s. Zablokowano zapisane w klipie przesunięcie bioder, aby model nie odjeżdżał od kolizji i nie dublował wysokości skoku. Skok działa również podczas marszu/biegu; kamera swobodna nie zatrzymuje opadania. To skok sterowany fizyką, bez automatycznego wykrywania i przeskakiwania przeszkód. [Faza lotu](artifacts/agnes_jump_apex.png).
- Theia usunięta z grywalnej gry: `--theia` i przełącznik `-Theia` w `START.ps1` zostały usunięte, grywalną postacią jest wyłącznie Agnes. Kopie modeli Agnes przygotowuje `tools/prepare_agnes.py`; animacje używają jednej wspólnej tekstury. Oryginały w `artifacts/sprites/agnes` pozostają bez zmian. Emisję materiałów wyłączono, aby postać reagowała na światło i cienie.

- Gęste proceduralne tło tysięcy gwiazd oraz ilustracyjna Droga Mleczna: pas skupisk gwiazd, jaśniejsze centrum i nieregularne smugi pyłu. Tło jest nieruchome względem nieba i zasłaniane przez teren, Ziemię oraz Słońce. Powstaje w shaderze bez osobnych obiektów dla każdej gwiazdy; nie jest fotograficzną ani pomiarową mapą Galaktyki. [Aktualny podgląd](artifacts/starfield.png).

- 32 najjaśniejsze gwiazdy: katalogowe pozycje względne, jasność oparta na magnitudo i przybliżone barwy typów widmowych. Gwiazdy nie migoczą, nie przesuwają się wraz z postacią i są zasłaniane przez teren oraz tarcze Ziemi i Słońca. Orientacja całego katalogu względem horyzontu jest artystyczna, bez wyliczania daty i księżycowej pozycji obserwatora. Rozmiar punktów i kontrast dostosowano do czytelności w grze. [Podgląd gwiazd](artifacts/starfield.png).

- Widoczna tarcza Słońca zgodna z kierunkiem oświetlenia oraz Ziemia z teksturą NASA Blue Marble, obrotem i niebieską obwódką. Ziemia wyłania się zza terenu i znika pod horyzontem. W pauzie sekcja „Niebo” pozwala zatrzymać cykl, wybrać 45 sekund / 3 minuty / 9 minut oraz ręcznie ustawić jego fazę. Cykl i rozmiary tarcz są umowne, dostosowane do gry — nie są efemerydą astronomiczną. Słońce pozostaje nieruchome podczas cyklu Ziemi. [Wschód](artifacts/sky_earthrise.png), [zachód](artifacts/sky_earthset.png).
- Cienie Słońca używają atlasu 4096 i płynnych przejść między kaskadami; zmniejszono odsunięcie cienia od powierzchni przy niskim oświetleniu. Wyłączono emisję w importowanym materiale Thei, aby reagowała na cień terenu. Kamera przy przeszkodach skraca ramię bez bocznych przeskoków i łagodnie wraca do zadanej odległości.

- Grywalny sektor przy **Silesii**, ze współrzędnymi roboczymi 82°S, 30°E. Punkt terenowy jest makietą do testowania skali i ruchu.
- Lekki glob: prawdziwa mapa barw LROC 4096×2048, zachowana w pełnej rozdzielczości, i wysokości LOLA 1440×720. Model globu ma rzeczywistą proporcję reliefu, bez sztucznego powiększenia wysokości.
- Materiał podłoża: drobny regolit, dwa rozmiary kamyków, wypukłość w skali świata, mapa szumu 2048² z mipmapami i filtrowaniem anizotropowym 16×. Drobne detale wygasają poniżej wielkości piksela. Theia używa współdzielonego atlasu 4K.
- Najgrubszy globalny DEM (4 piksele/stopień, ~7,6 km/piksel) pozostaje ostatecznym fallbackiem tam, gdzie brakuje kafla mezo. **Żaden z tych zbiorów to nie lokalny NAC DEM ani SLDEM2015.** Drobne kratery, skały i regolit w sektorze są proceduralną warstwą gry; mapa pokrycia jest klasyfikacją na podstawie nachylenia, nie pomiarem geologicznym.
- Warstwa mezo: LOLA 64 px/stopień (~474 m/piksel na równiku), 23040×11520, pocięta na kafle 512×512 (uint16, offset −10000 m, krok 0,5 m) w `godot/assets/moon/meso`; wczytywana leniwie z dyskowym cache LRU (48 kafli, ~24 MiB) w `lunar_meso_dem.gd`. Siatka to sześciościenna quadtree zagęszczana wokół kamery (`lunar_orbit_lod.gd`, do poziomu 12); nowe kafle wyrastają z powierzchni rodzica do zmierzonej wysokości w 0,65 s (shader `meso.gdshader`), więc podejście z orbity do lokalnego terenu jest ciągłe — bez cięcia ekranu ani zmiany skali Księżyca. Przekazanie kamery lokalnemu terenowi następuje, gdy ślad kamery na gruncie mieści się już w całości w zdjętym obszarze 2 m (`lunar_terrain.survey_margin`), a nie na sztywnej wysokości — przy dużym zdjęciu (Tycho) dzieje się to już kilka kilometrów nad gruntem, bez lądowań poza zdjęciem (tam obowiązuje stały próg 240 m).
- W ZIP-ie jest symulacja gospodarcza, nie gotowe lokacje 3D. Wczytano jej 14 publicznych lokacji i 21 tras do `assets/moon/colonies.json`. Glob pokazuje lokacje; trasy i gospodarka nie są jeszcze rozgrywką Godota. Theia pełni rolę postaci testowej zamiast docelowego Siwego-04.
- Przygotowano adapter GeoServera oraz klienta HTTP z cache. **Żaden rzeczywisty GeoServer ani lokalny NAC DEM nie jest jeszcze skonfigurowany.** Domyślnie działa wariant offline. Adresy, nazwy warstw i współrzędne konfiguracji serwera są przykładami.

## Streaming zamiast całego globu

Kafel ma 64×64 m. Otoczenie 5×5 kafli ma siatkę co 2 m, kolizje i skały. Dalszy pierścień do 11×11 kafli ma siatkę co 8 m, bez kolizji i skał. W pamięci jest najwyżej 121 aktywnych kafli; zamieniany węzeł może istnieć do końca bieżącej klatki. Nowy kafel powstaje co klatkę, najbliższe mają pierwszeństwo. Początkowe dziewięć jest przygotowane przed dodaniem postaci. Ruch na jeszcze niegotowy kafel jest zatrzymywany.

Przy przesuwaniu postaci zwalniane są siatki, kolizje, instancje skał i cache wysokości poza promieniem. Ślady mają limit 160. Cache dyskowy serwera i gry ma osobne limity. Glob nawigacyjny tworzony jest dopiero po naciśnięciu M; nie zawiera geometrii grywalnej dla wszystkich kolonii.

To lokalna płaszczyzna styczna, nie ciągłe chodzenie po całej kuli. Podejście z orbity nad wybrany punkt jest już ciągłe (warstwa mezo LOLA rośnie w szczegóły bez cięcia ekranu); przejścia między odległymi lokacjami i przesuwanie początku układu współrzędnych przy długiej jeździe to następne etapy. Przy locie do innej kolonii należy zwolnić sektor i utworzyć nowy, zamiast utrzymywać wszystkie sceny. Cel podejścia można wskazać przeciągnięciem po globie (dowolny punkt, nie tylko znane kolonie) albo klawiszem **N** — lista 14 kolonii plus własne współrzędne szerokości/długości.

## Dane i projekt

- [Architektura GeoServera i dobór lokacji](docs/TERRAIN_ARCHITECTURE.md).
- [Instrukcja uruchomienia adaptera](services/README.md).
- Oryginał ZIP-a pozostawiono bez zmian; rozpakowana zawartość: `design/lunar_inpost_strategy`.
- Oryginały map NASA: `source_data`; konwersja: `tools/prepare_assets.py` (Python, NumPy, Pillow, tifffile).
- Theia i animacje skopiowane z `D:/projects/elvenpass/godot_playable/assets/sprites/theia`. Projekt źródłowy nie był modyfikowany. Zachowano oryginalne modele; materiały w grze mają zmniejszoną metaliczność.
- [Podgląd powierzchni](artifacts/surface.png), [podgląd globu](artifacts/globe.png).

## Sprawdzenie

`--script res://tests/backpack_test.gd -- --camera-test` sprawdza brak skórowania plecaka, mocowanie do tułowia i stałe wymiary w 30 pozach sześciu animacji; zapisuje widoki z tyłu i z boku. `--headless` pomija zrzuty.

`--script res://tests/leg_spacing_test.gd -- --camera-test` porównuje rozstaw kości ud w czterech fazach chodu i biegu, a także zapisuje podgląd kroku.

`--script res://tests/helmet_test.gd -- --camera-test` sprawdza mocowanie i skalę hełmu w sześciu animacjach, przełączanie H, filtrowanie FPP, pauzę i ukrycie filtra na globie; zapisuje zbliżenia hełmu. `tools/cut_helmet.py` sprawdza granicę geometrycznego wycięcia spodu.

Test `--smoke-test` sprawdza Agnes (w tym idle); postać Theia została usunięta z grywalnej gry, flaga `--theia` już nie istnieje. `--script res://tests/agnes_preview.gd -- --camera-test` uruchamia podgląd sześciu animacji Agnes i zapisuje `artifacts/agnes_*.png`. `--script res://tests/jump_test.gd -- --camera-test` sprawdza skok, usunięcie przesunięcia z animacji, blokadę drugiego skoku w powietrzu, pauzę, lądowanie podczas swobodnego lotu kamerą i powrót do idle; zapisuje podglądy `agnes_jump_*.png` (wariant `--headless` pomija obrazy).

`tools/godot/Godot_v4.6.1-stable_win64_console.exe --path godot --script res://tests/camera_test.gd -- --camera-test` sprawdza nieruchomą Theię podczas dwóch pełnych obrotów kamery, reakcję na przeszkodę i łagodny powrót oraz materiał przyjmujący cienie. Zapisuje osiem widoków `artifacts/orbit_after_*.png`. Wariant `--headless` pomija obrazy.

`python -m unittest discover -s services -v` sprawdza granice, orientację rastra, halo normalnych, ujemne indeksy, NoData, HTTP i cache adaptera. `python services/verify_godot_client.py` sprawdza rzeczywistego klienta Godota przez HTTP z kontrolowanym rastrem testowym.

`tools/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path godot -- --smoke-test` sprawdza kontakt z podłożem, ruch, animacje, kolizje kolejnych kafli, limit pamięci i przełączanie globu. Testy serwera korzystają z syntetycznego rastra analitycznego, nie z uruchomionej instalacji GeoServera. Scenę obejrzano również w renderze OpenGL.

## Źródła

Gwiazdy: Fred Espenak / AstroPixels, [50 Brightest Stars](https://astropixels.com/stars/brightstars.html), pierwsze 32 pozycje zestawienia opartego na Hipparcos; zaokrąglone RA/Dec J2000 i magnitudo V. Dane w `godot/scripts/bright_stars.gd`.

Ziemia: NASA Scientific Visualization Studio, [Blue Marble](https://svs.gsfc.nasa.gov/2915/), mapa 2048×1024. Na rzeczywistym Księżycu pozycja Ziemi na niebie zmienia się niewiele; jej wschód i zachód zależy od lokalizacji i libracji ([NASA StarChild](https://starchild.gsfc.nasa.gov/docs/StarChild/questions/question58.html)).

NASA's Scientific Visualization Studio / Ernie Wright, **CGI Moon Kit**: https://svs.gsfc.nasa.gov/4720/. Mapa barw: LROC WAC, wariant 2019 `lroc_color_poles_4k.tif`. Wysokości (warstwa najgrubsza): LOLA `ldem_4_uint.tif`, 4 px/stopień, przeliczenie `wartość × 0,5 − 10000` metrów względem promienia 1 737 400 m. Wysokości (warstwa mezo): LOLA 64 px/stopień z tej samej strony CGI Moon Kit, ten sam przelicznik; kafle przygotowuje `tools/prepare_meso_dem.mjs`. Mapy CGI są opracowaniem do wizualizacji; do badań służą źródłowe produkty PDS.
