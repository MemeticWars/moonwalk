# Współpraca agentów

Repozytorium jest wspólnym obszarem pracy agentów Codex i Claude. Zmiany jednej strony są natychmiast widoczne dla drugiej, więc współpraca opiera się na małych, rozłącznych zmianach oraz na zachowaniu aktualnego stanu plików.

## Podział pracy

- Zadanie powinno mieć jasno określony zakres plików i odpowiedzialności; jeśli da się go podzielić, każdy agent bierze inny moduł, test lub dokument.
- Agent nie zaczyna równolegle przebudowy tego samego systemu. Gdy potrzebna jest zmiana wspólnego pliku, ogranicza ją do małego fragmentu potrzebnego do swojego zadania.
- Zmiana przekrojowa wymaga opisania decyzji i miejsc, których dotyczy, w odpowiednim pliku `index/`, aby drugi agent mógł bez zgadywania kontynuować pracę.

## Praca w tym samym katalogu

1. Przed czytaniem lub edycją sprawdź `git status --short` oraz diff plików, których dotknie zadanie. Traktuj każdą obecną zmianę jako cudzą, dopóki jej nie rozpoznasz.
2. Edytuj małym patchem w obrębie własnego zakresu. Nie cofaj, nie przenoś, nie formatuj masowo i nie „porządkuj” zmian drugiego agenta.
3. Przed testem lub zapisem ponownie sprawdź diff własnych plików. Jeśli w międzyczasie pojawiła się obca zmiana w tym samym fragmencie, zachowaj ją, dopasuj własną zmianę albo wstrzymaj zależną część pracy i opisz konflikt.
4. Uruchamiaj tylko testy właściwe dla zmienionego obszaru i podawaj ich wynik. Nie poprawiaj przy okazji niezwiązanych błędów testów; odnotuj je jako istniejące poza zakresem.
5. Jeśli zlecona praca prowadzi do konfliktu z bieżącym kodem lub nieukończoną zmianą drugiego agenta, a nie da się go bezpiecznie rozdzielić małym patchem, agent odmawia wykonania tej części zadania i podaje plik oraz fragment stanowiący konflikt. Nie wymusza scalenia, nie nadpisuje pracy drugiego agenta i nie zgaduje jej zamierzonego zachowania.
6. Automatyczne testy Godota uruchamiaj przez `--headless`. Gdy konieczny jest render w oknie, dodaj argument użytkownika `--agent-run`; nie uruchamiaj gry w zwykłym trybie interaktywnym, ponieważ może przejąć kursor użytkownika.
7. Przed dłuższym uruchomieniem Godota (test, `--headless`, `--agent-run`) sprawdź tabelę „Aktywna praca” w `AGENTS.md` i dopisz do niej swój wiersz — równoległe procesy Godota potrafią uszkodzić wspólny cache importu (`.godot/imported/`), co objawia się fałszywymi błędami kompilacji lub crashem silnika niezwiązanym z żadną realną zmianą w kodzie. Nieudany `assert()` w GDScripcie nie kończy procesu automatycznie; po takim teście ubij go ręcznie, zanim uruchomisz kolejny.

## `--agent-run`

`--agent-run` jest argumentem użytkownika projektu, a nie przełącznikiem silnika Godot. Podczas okienkowego uruchomienia informuje `moonwalk.gd` i kontrolery postaci, że proces należy do agenta: gra nie przechwytuje, nie ukrywa ani nie ogranicza kursora do swojego okna.

Stosuj go wyłącznie, gdy rzeczywiście potrzebny jest render lub ręczne obejrzenie sceny; testy bez obrazu nadal uruchamiaj przez `--headless`. Przykład: `Godot --path godot --agent-run`; proces należy wpisać do tabeli aktywnej pracy przed startem i zakończyć przed usunięciem wpisu.

## Commity i przekazanie pracy

- Staging i commit obejmują wyłącznie pliki oraz linie należące do bieżącego zadania. Przed commitem należy sprawdzić `git diff --cached` i nie używać `git add .` ani szerokiego formatowania repozytorium.
- Komunikat commita i opis przekazania podają problem, zmienione zachowanie, kluczowe pliki oraz wykonane testy. Jeśli praca pozostaje nieukończona, należy jasno zostawić następny krok i ograniczenia, zamiast oznaczać ją jako zakończoną.
- Wspólne, trwałe ustalenia zapisuje się zwięźle w `AGENTS.md`, a szczegóły w odpowiednim `index/*.md`. `AGENTS.md` jest krótkim indeksem spraw, a pliki w `index/` zawierają wiedzę potrzebną do dalszej pracy.
