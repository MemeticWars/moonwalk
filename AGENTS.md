# Indeks spraw

Ten plik jest indeksem spraw projektu i służy agentom jako pierwszy punkt orientacji. Każda sprawa ma tutaj dwa zdania opisu, a trzecie zdanie wskazuje plik z pełnymi szczegółami.

## Świat i fabuła

Gra opowiada o kurierze InPost na Księżycu po wojnie odcinającej kolonie od Ziemi, podzielonym między frakcje (górnicy, chińskie miasto, Space Navy, naukowcy, miliarderzy, piraci, ukryta Wspólnota Modelu). Mechanicznie istnieje na razie tylko prototyp symulacji ekonomicznej w Pythonie, niepodłączony do gry w Godocie. Szczegóły fabuły, frakcji i stanu implementacji są w [index/world.md](index/world.md).

## Współpraca agentów

Nad tym repozytorium jednocześnie pracują agenci Codex oraz Claude. Zmiany należy ograniczać do własnego zadania, sprawdzać stan Git przed edycją i nie nadpisywać bieżącej pracy drugiego agenta; `--agent-run` jest argumentem użytkownika rozpoznawanym przez skrypty gry, który pozostawia widoczny i nieograniczony kursor podczas renderu okienkowego. Szczegóły zasad współpracy, trybu `--agent-run` i zasad uruchamiania Godota są w [index/collaboration.md](index/collaboration.md).

### Aktywna praca

Przed rozpoczęciem zadania dopisz wiersz do tabeli, a po scommitowaniu lub porzuceniu pracy natychmiast go usuń — pusta tabela jest stanem domyślnym, nie wyjątkiem.

| Agent | Zakres (pliki/moduł/uruchomiony Godot) | Rozpoczęto (UTC) |
|---|---|---|
| _(brak aktywnej pracy)_ | | |

Zasady: sprawdź tabelę, zanim zaczniesz edytować lub uruchomisz Godota — nakładający się zakres oznacza czekanie albo zawężenie się do rozłącznej części. Wpis obejmuje też dłuższe uruchomienie Godota (test, `--headless`, `--agent-run`), bo równoległe procesy Godota potrafią uszkodzić wspólny cache importu (`.godot/imported/`) i dawać fałszywe błędy kompilacji — nie tylko konflikt plików wymaga zgłoszenia. Wpis starszy niż ok. 2h bez aktualizacji traktuj jako potencjalnie porzucony, ale zweryfikuj to (`git log`, `git status`) zamiast go po prostu kasować. Po nieudanym teście z `assert()` proces Godota zwykle się nie kończy sam — ubij go, zanim zwolnisz swój wiersz.

## Autostrady między lokacjami

Projekt ma proceduralną sieć autostrad łączącą lokacje księżycowe oraz lokalne odcinki streamowane przy aktywnym sektorze. Następnym dużym zadaniem jest rozszerzenie tej sieci o długie połączenia między lokacjami bez ładowania całej trasy naraz. Szczegóły danych tras, generatora, ograniczeń spadku i testów są w [index/highways.md](index/highways.md).

## Postacie i wspinanie

Agnes jest jedyną grywalną postacią, a mechanika wspinania odrzuca otwory drzwiowe i używa pełzania na zaokrąglonych dachach. Wspólna warstwa humanoidów pozwala podłączyć model ze szkieletem do biblioteki ruchów po mapowaniu kości. Szczegóły stanów ruchu, animacji i testów są w [index/characters.md](index/characters.md).

## Dane, teren i uruchamianie

Gra działa w Godot 4.6.1 i streamuje lokalny sektor księżycowy wokół aktywnej postaci. Duże assety i dane wysokościowe są poza Gitem, dlatego klon kodu wymaga ich osobnego dostarczenia. Szczegóły konfiguracji, źródeł danych i uruchamiania są w [index/project.md](index/project.md).

## Pojazdy i konwój

Agnes może prowadzić Lorry po wejściu klawiszem E, a za łazikiem jadą dwa ośmiokołowe, teksturowane drony transportowe, parkujące na wyznaczonych stanowiskach przy śluzie Tycho. Pojazdy korzystają z fizyki księżycowej, ograniczonej przyczepności oraz wspólnego sterowania napędem, a drony śledzą trasę poprzednika i zachowują odstęp. Szczegóły sterowania, implementacji i testów są w [index/vehicles.md](index/vehicles.md).

## Ciągłość terenu

Geometria terenu i wspólne krawędzie kafli muszą być deterministyczne dla tych samych danych oraz poziomów LOD, niezależnie od kolejności wczytywania. Wyrównania pod zabudowę wymagają aktualizacji już utworzonych siatek i kolizji, a horyzont nie może nakładać większych kafli na lokalny grunt. Szczegóły implementacji i testów są w [index/terrain.md](index/terrain.md).

## Stawy i potok Tycho

Stawy w D1 i m3 mają rzeczywiste niecki głębokie odpowiednio na 1 m i 1,5 m, a łączący je potok ma przekrój U, szerokość 50 cm i głębokość 50 cm. Deterministyczna trasa z zaokrąglonymi zakrętami omija zabudowę i biegnie przez tunel D1–m3 przy jednej ścianie, obok uliczki dla pieszych szerokiej na 2,4 m. Szczegóły geometrii, kolizji, wspólnych danych i testów są w [index/water.md](index/water.md).

## Narzędzia assetów Tycho

Skrypty przygotowujące pojedyncze assety Tycho leżą w `tools/` i noszą nazwę `prepare_tycho_*.py`, obok pozostałych skryptów tej rodziny. Ich opis oraz komendy przebudowania kopii gry należą do `godot/assets/colonies/tycho/README.md`; nie dopisuj przy okazji nieobjętych zmianą starszych skryptów do jego listy przebudowania.

Szczegółowy wzorzec, w tym `prepare_tycho_habitat_tunnel.py` i `prepare_tycho_fish.py`, jest w [index/project.md](index/project.md#narzędzia-przygotowania-assetów-tycho).
