# Projekt, dane i uruchamianie

Projekt działa w Godot 4.6.1 z rendererem Forward+; sceną główną jest `godot/scenes/moonwalk.tscn`. Grę uruchamia `START.ps1`, a edytor otwiera przełącznik `-Editor`.

Git zawiera kod, sceny, shadery, dokumentację i narzędzia, lecz nie zawiera ciężkich modeli, tekstur ani danych terenu. Po klonowaniu trzeba dostarczyć `godot/assets/`, `source_data/` oraz opcjonalne `artifacts/sprites/`; kafle sektorów mogą wymagać rozpakowania archiwów z nośnika assetów.

Teren składa się z lokalnie streamowanych kafli, warstwy mezo LOLA i fallbacku globalnego DEM. Przejścia między dalekimi lokacjami odbywają się przez glob i zmianę aktywnego sektora, a nie ciągły świat 3D całego Księżyca.

Szczegółowe opisy architektury terenu są w `docs/TERRAIN_ARCHITECTURE.md`, usługi danych w `services/README.md`, a historyczne uwagi produktu w `README.md`.

## Assety: Git vs Google Drive

Git (`origin/main`, `git@github.com:MemeticWars/moonwalk.git`) trzyma tylko kod: `godot/scripts`, `godot/scenes`, `godot/shaders`, `godot/addons`, `docs/`, `tools/*.py`, `tools/*.mjs`, `README.md`. Google Drive trzyma `godot/assets/`, `source_data/` i `artifacts/sprites/`; link do folderu jest w `.env` pod kluczem `google_drive` — nie wypisuj zawartości `.env` w czacie ani w commitach. Silnik (`tools/godot/`) nie jest w żadnym z nich, to zwykła dystrybucja 4.6.1 z godotengine.org.

Przed dodaniem nowego dużego pliku do `godot/assets/` sprawdź, czy istnieje faktyczna referencja `res://...` w `scripts`/`scenes`/`shaders`. Jeśli nie — to wejście dla narzędzia (`tools/`), miejsce dla niego jest `source_data/`; tak przeniesiono `godot/assets/moon/dem_real` do `source_data/dem_real/{tycho,south_pole}`, bo `bake_sector_dtm.mjs` używa go offline, a gra nigdy. Kafle terenu (`godot/assets/sectors/*`, `godot/assets/moon/meso/`) to po kilka tysięcy małych plików — zawsze pakuj je w `.zip` przed wysyłką na Drive (`Compress-Archive`), odbiorca rozpakowuje do folderu o nazwie archiwum.

rclone używa własnego OAuth `client_id`/`client_secret` (w `.env`), nie domyślnego współdzielonego — ten ma globalny limit zapytań do Drive API, który potrafi zawiesić duży transfer w cichej pętli powtórek bez widocznego błędu. Remote `gdrive` jest już skonfigurowany w `%APPDATA%\rclone\rclone.conf`; do odtworzenia od zera potrzeba interaktywnego `rclone authorize` i `rclone config create` z kluczem z `.env`.

Klucz SSH do GitHuba (`MemeticWars`) to `~/.ssh/key`, nie domyślny `id_ed25519` — wskazany jawnie przez `git config core.sshCommand "ssh -i ~/.ssh/key -o IdentitiesOnly=yes"` lokalnie w tym repo, tak samo jak `user.name`/`user.email`.

## Testy: lokalny silnik, headless, nie ufaj samym testom jednostkowym

Lokalny silnik jest w `tools/godot/Godot_v4.6.1-stable_win64_console.exe`. Testy `res://tests/*.gd` (rozszerzają `SceneTree`) odpala się przez `--headless --path godot --script tests/<nazwa>.gd`; testy sterowane samą grą (`--smoke-test`, `--climb-test`, `--road-test` i inne flagi w `moonwalk.gd`) potrzebują pełnej sceny: `--headless --path godot scenes/moonwalk.tscn -- --climb-test`. `--smoke-test` potrafi trwać dłużej niż 90 s — nie ucinaj go krótkim timeoutem, inaczej brak wyniku wygląda jak cichy fail. Stały szum silnika przy `quit()` w headless (`ERROR: BUG: Unreferenced static string`, `Pages in use exist`, ostrzeżenie o Thread) nie jest błędem.

Testy jednostkowe z syntetycznymi pudełkami kolizji przechodzące zielono NIE dowodzą, że mechanika działa w realnej grze — pełna historia (wspinaczka działała w testach, a nie działała wcale w grze) jest w [index/characters.md](characters.md). `--smoke-test`'s test biegu Q trafił na podobny problem: wcześniejszy krok testu (chodzenie) zużywał niemal cały wolny teren do bulkheadu bramy kopuły (`DomeCollision`), więc test biegu startował już dotykając kolizji — naprawione resetem pozycji w samym teście tuż przed segmentem biegu.
