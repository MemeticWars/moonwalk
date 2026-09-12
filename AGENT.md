# AGENT.md — jak jest zorganizowany ten projekt

Notatka dla przyszłych sesji agenta (i dla siebie z przyszłości). Kontekst: kod jest w gicie, ciężkie binarne assety leżą osobno na Google Drive. Historia tej decyzji i pułapki po drodze — niżej.

## Kod vs assety

- **Git** (`git@github.com:MemeticWars/moonwalk.git`, zdalne `origin`, gałąź `main`): tylko kod — `godot/scripts`, `godot/scenes`, `godot/shaders`, `godot/addons`, `docs/`, `tools/*.py`, `tools/*.mjs`, `README.md` itd. Zobacz `.gitignore` — sekcja "Heavy binary assets" wypisuje co jest wyłączone.
- **Google Drive**: `godot/assets/`, `source_data/`, `artifacts/sprites/`. Link do folderu jest w `.env` pod kluczem `google_drive` — **nie wypisuj zawartości `.env` w czacie ani w commitach**, tylko odczytuj potrzebną zmienną (np. `grep -oP '^google_drive=\K.*' .env`).
- Silnik Godota (`tools/godot/`) nie jest ani w gicie, ani na Drive — to zwykła dystrybucja 4.6.1, do pobrania z godotengine.org. Nie ma sensu go backupować.
- Pełna tabela wag i instrukcja "jak złożyć projekt od zera" jest w `README.md` (sekcja "Skład projektu: kod (GitHub) + assety (Google Drive)") — aktualizuj ją razem z tym plikiem, jeśli układ się zmieni.

## `godot/assets/moon/dem_real` przeniesione do `source_data/dem_real`

Surowe DEM-y (`NAC_DTM_TYCHOPK.TIF` ~1,5 GB, `ldem_87s_5mpp.tif` ~3,46 GB) siedziały pod `godot/assets/moon/dem_real/`, ale **żaden `res://` w grze się do nich nie odwołuje** — to wejście offline dla `tools/bake_sector_dtm.mjs` (ta sama rola co `source_data/*.tif`), nie asset ładowany w runtime. Przeniesione do `source_data/dem_real/{tycho,south_pole}/`; ścieżki `tiff:` w `SOURCES` w `bake_sector_dtm.mjs` już to odzwierciedlają. **Jeśli coś znowu wyląduje pod `godot/assets/moon/dem_real` — to prawdopodobnie ten sam błąd, przenieś to z powrotem do `source_data/`.**

Ogólna zasada przy dorzucaniu nowych dużych plików: zanim wrzucisz coś do `godot/assets/`, sprawdź czy faktycznie jest referencja `res://...` w `scripts`/`scenes`/`shaders` (grep). Jeśli nie — to prawdopodobnie wejście dla narzędzia (`tools/`), miejsce dla niego to `source_data/`.

## Kafle terenu: pakuj w zip przed wysyłką na Drive

`godot/assets/sectors/{tycho_station,lubin_deep,shackleton_ice}/` i `godot/assets/moon/meso/` to po **tysiące plików `.bin` po kilka KB** (łącznie >8000 plików). Wysyłanie ich do Google Drive plik-po-pliku jest niewykonalne — każdy plik to osobne wywołanie API, ETA leci w dni, i szybko wypala limit zapytań. **Zawsze pakuj te foldery w `.zip` przed wysyłką**, np.:

```powershell
Compress-Archive -Path "godot\assets\sectors\tycho_station\*" -DestinationPath "tycho_station.zip"
```

Wgrywaj `<sektor>.zip` do `gdrive:godot/assets/sectors/` (albo `meso.zip` do `gdrive:godot/assets/moon/`). Kto ściąga z Drive, musi je rozpakować do folderu o nazwie archiwum (np. `tycho_station.zip` → `godot/assets/sectors/tycho_station/`) — patrz README.

## rclone: zawsze używaj własnego OAuth client_id, nie domyślnego

Domyślny, współdzielony `client_id` rclone (ten sam dla wszystkich użytkowników rclone na świecie) ma limit `defaultPerMinutePerProject` na Google Drive API. Ten limit jest **globalny**, więc nawet pojedynczy duży upload (jeden plik 396 MB) potrafi w niego wpaść pod koniec transferu i zawiesić się w nieskończonej pętli powtórek bez widocznego błędu (widać to dopiero z `-vv` jako `rateLimitExceeded`/`quotaExceeded`).

Rozwiązanie: w Google Cloud Console założony jest osobny projekt z włączonym Drive API i własnym OAuth client (typ **Desktop app**, tryb **Testing**, `mawroc@gmail.com` dodany jako **test user**). `client_id` i `client_secret` są w `.env`. Remote `gdrive` w lokalnym `rclone.conf` (`%APPDATA%\rclone\rclone.conf`) jest już skonfigurowany z tym kluczem i tokenem (`root_folder_id` wskazuje na folder z `google_drive` w `.env`) — **nie trzeba tego robić od nowa**, chyba że token wygaśnie bez ważnego `refresh_token` albo remote zniknie.

Jeśli trzeba odtworzyć remote od zera:
```bash
RCLONE="ścieżka/do/rclone.exe"
CLIENT_ID=$(grep -oP '^client_id=\K.*' .env)
CLIENT_SECRET=$(grep -oP '^client_secret=\K.*' .env)
FOLDER_ID=$(grep -oP '^google_drive=.*folders/\K[^?]*' .env)
# authorize wymaga interaktywnego logowania w przeglądarce -- poproś użytkownika
# o odpalenie tego przez "! ..." i wklejenie zwróconego JSON-a z tokenem:
"$RCLONE" authorize "drive" "$CLIENT_ID" "$CLIENT_SECRET"
"$RCLONE" config create gdrive drive scope=drive root_folder_id="$FOLDER_ID" client_id="$CLIENT_ID" client_secret="$CLIENT_SECRET" token='<wklejony JSON>'
```

rclone binarka jest zainstalowana przez `winget install --id Rclone.Rclone` (nie w PATH tej sesji bez restartu shella — pełna ścieżka zwykle pod `C:\Users\<user>\AppData\Local\Microsoft\WinGet\Packages\Rclone.Rclone_*\rclone-*-windows-amd64\rclone.exe`, sprawdź `Get-Command rclone` po restarcie).

## Testy w Godocie: headless, lokalny silnik, nie ufaj samym testom jednostkowym

Lokalny silnik jest pod `tools/godot/Godot_v4.6.1-stable_win64_console.exe` (patrz wyżej — nie jest w gicie ani na Drive, zwykła dystrybucja 4.6.1). Testy `res://tests/*.gd` (rozszerzają `SceneTree`) odpala się tak:

```bash
cd godot
"../tools/godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path . --script tests/human_motion_test.gd
```

Testy uruchamiane przez samą scenę gry (`--smoke-test`, `--climb-test` i inne flagi w `moonwalk.gd`'s `_ready()`) potrzebują sceny, nie samego `--script`:

```bash
"../tools/godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path . scenes/moonwalk.tscn -- --climb-test
```

`--smoke-test` przechodzi przez cały globe/highways/pauzę i potrafi trwać dłużej niż 90 s w headless — nie ucinaj go za krótkim timeoutem, inaczej brak wyniku wygląda jak cichy fail. Stały szum w stderr (`ERROR: BUG: Unreferenced static string to 0: ...`, `Pages in use exist at exit`, ostrzeżenie o Thread) to normalne artefakty silnika przy `quit()` w headless, nie prawdziwe błędy — odfiltruj przez `grep -viE "^ERROR: BUG|Unreferenced|paged_allocator|Thread object|wait_to_finish|RID alloc"`.

**Testy jednostkowe (`godot/tests/*.gd`, syntetyczne pudełka kolizji) przechodzące zielono NIE dowodzą, że mechanika działa w realnej grze.** Przykład z 2026-09-12: generalizacja wspinaczki (`human_controller.gd`) miała `_solid_climb_patch()` wymagający zgodności głębi (≤0,35 m) między 9 promieniami na różnych wysokościach, żeby odrzucić drzwi. Syntetyczne pudełko w teście miało głębię 0 (płaska ściana) — przechodziło. Prawdziwa fasada budynku w Tycho (cokół, opaski okienne) ma naturalną różnicę głębi ~0,4-0,5 m — próg odrzucał niemal cały środek prawdziwej ściany, więc wspinaczka nie działała w ogóle w grze mimo zielonych testów. Namierzone dopiero przez `--climb-test` na realnym budynku ("twin-houses") z ręcznym sondowaniem promieni na różnych `x`. Wniosek: po zmianie progu geometrycznego (kolizje, normalne, odległości) zawsze też przepuść `--climb-test`/`--smoke-test` na prawdziwej scenie, nie tylko testy syntetyczne.

Naprawa: odrzucanie drzwi przeniesione całkowicie do `_doorway_ahead(direction)`, wywoływanego teraz per-kierunek wewnątrz pętli zamiatania w `_nearest_climb_surface()` (wcześniej sprawdzane tylko dla kierunku, w którym postać akurat patrzyła — omijało drzwi trafione przez sam sweep). `_solid_climb_patch()` sprawdza już tylko, czy wszystkie 9 promieni trafia w litą, prawie pionową powierzchnię.

`--smoke-test`'s test "Q alone must run forward" (Elvenpass Q-bieg) też trafił na realny problem geometrii: wcześniejszy krok testu (`move_forward` przez 2 s) zużywa niemal cały wolny teren między wejściem na stację (`TYCHO_PLAYER_START`) a bulkheadem bramy kopuły (`DomeCollision`, patrz [[tycho-dome-gate-bulkhead]]) — test biegu Q startował więc z Theią już dotykającą kolizji kopuły, i prędkość zerowana przez ścianę czytała się jak "Q nie działa". Naprawione w samym teście: `theia.position` i `velocity` są resetowane z powrotem do zapamiętanego `start` tuż przed segmentem biegu Q, żeby test miał świeży odcinek wolnego terenu niezależnie od tego, ile zjadł wcześniejszy krok chodzenia.

## Git: SSH klucz i tożsamość

- Klucz SSH do GitHuba (konto `MemeticWars`) to `~/.ssh/key` (nie domyślna nazwa `id_ed25519`), więc trzeba go wskazać jawnie — w tym repo jest to zrobione lokalnie: `git config core.sshCommand "ssh -i ~/.ssh/key -o IdentitiesOnly=yes"`.
- Tożsamość gita ustawiona lokalnie w tym repo (`user.name = MemeticWars`, `user.email = mawroc@gmail.com`) — nie globalnie.
