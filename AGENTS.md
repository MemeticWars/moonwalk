# Indeks spraw

Ten plik jest indeksem spraw projektu i służy agentom jako pierwszy punkt orientacji. Każda sprawa ma tutaj dwa zdania opisu, a trzecie zdanie wskazuje plik z pełnymi szczegółami.

## Współpraca agentów

Nad tym repozytorium jednocześnie pracują agenci Codex oraz Claude. Zmiany należy ograniczać do własnego zadania, sprawdzać stan Git przed edycją i nie nadpisywać bieżącej pracy drugiego agenta. Szczegóły zasad współpracy są w [index/collaboration.md](index/collaboration.md).

## Autostrady między lokacjami

Projekt ma proceduralną sieć autostrad łączącą lokacje księżycowe oraz lokalne odcinki streamowane przy aktywnym sektorze. Następnym dużym zadaniem jest rozszerzenie tej sieci o długie połączenia między lokacjami bez ładowania całej trasy naraz. Szczegóły danych tras, generatora, ograniczeń spadku i testów są w [index/highways.md](index/highways.md).

## Postacie i wspinanie

Agnes jest jedyną grywalną postacią, a mechanika wspinania odrzuca otwory drzwiowe i używa pełzania na zaokrąglonych dachach. Wspólna warstwa humanoidów pozwala podłączyć model ze szkieletem do biblioteki ruchów po mapowaniu kości. Szczegóły stanów ruchu, animacji i testów są w [index/characters.md](index/characters.md).

## Dane, teren i uruchamianie

Gra działa w Godot 4.6.1 i streamuje lokalny sektor księżycowy wokół aktywnej postaci. Duże assety i dane wysokościowe są poza Gitem, dlatego klon kodu wymaga ich osobnego dostarczenia. Szczegóły konfiguracji, źródeł danych i uruchamiania są w [index/project.md](index/project.md).
