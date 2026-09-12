# Lunar InPost Strategy v2

Prototyp strategicznej warstwy narracyjnej gry o kurierze InPost na Księżycu.

## Główna zasada

Księżyc jako całość produkuje prawie dość zasobów, żeby przeżyć, ale poszczególne kolonie są wyspecjalizowane i zależne od wymiany. Sieć InPost ma za małą przepustowość, aby uratować każdy kryzys. Dlatego **jeden kurs gracza na turę może zmienić wynik kampanii**.

Jedna tura = 3 dni. Kampania = 12 tur / 36 dni.

## Zasoby

- `LIFE` — woda i tlen
- `FOOD` — żywność
- `PARTS` — części, elektronika, maszyny
- `FUEL` — paliwo i zasoby transportowe
- `L$` — Lunar Dollar; waluta obiegu gospodarczego

Blooming Flower jest celowo najbardziej samowystarczalnym kompleksem na Księżycu. Reszta świata jest znacznie bardziej uzależniona od transportu.

## Co dzieje się autonomicznie

- produkcja i konsumpcja kolonii,
- niedobory, spadki stabilności i zgony,
- ograniczona sieć transportowa NPC InPost,
- ataki piratów na rzeczywiste korytarze,
- awarie i naprawy dróg,
- satelity komunikacyjne,
- rywalizacja Space Navy–Blooming Flower,
- wzrost napięcia w Silesii,
- ukryty rozwój Wspólnoty Modelu.

Świątynia Modelu **nie jest publicznym węzłem mapy**. Jej istnienie może zostać wykryte przez podejrzane transporty i późniejszą warstwę narracyjną.

## Co robi gracz

Gracz to `Siwy-04`. W każdej turze wybiera maksymalnie jeden strategiczny kurs. Może:

1. dostarczyć ładunek zgodnie z kontraktem,
2. samowolnie przekierować go do bardziej potrzebującej kolonii,
3. sprzedać ładunek piratom,
4. zrezygnować z kursu.

Transport może dotyczyć zasobów, pasażerów, ewakuacji albo ładunków wojskowych.

### Skutki decyzji

- ratowanie kolonii zwiększa stabilność i zaufanie,
- dostawy wojskowe zwiększają siłę frakcji i napięcie wojenne,
- luksusowe kontrakty dają dużo L$, ale zajmują jedyny kurs gracza,
- przekierowanie ratuje ludzi, ale łamie kontrakt i szkodzi reputacji/neutralności,
- handel z piratami wzmacnia rozbójników i osłabia całą sieć,
- tajne dostawy mogą ujawnić istnienie ukrytej Wspólnoty.

## Uruchomienie

Interaktywnie:

```bash
python main.py --interactive
```

Automatyczna kampania humanitarna:

```bash
python main.py --policy humanitarian
```

Porównanie różnych zachowań tego samego kuriera w identycznym świecie początkowym:

```bash
python main.py --compare
```

Dostępne polityki:

- `skip` — gracz nie interweniuje,
- `humanitarian` — priorytet życie i ewakuacja,
- `network` — ratowanie najbardziej niestabilnych węzłów,
- `profit` — maksymalizacja zarobku,
- `military_navy` — preferowanie zleceń Space Navy.

## Po co jest `--compare`

To test projektowy. Jeśli różne polityki kończą się praktycznie identycznie, decyzje gracza są pozorne. Obecna wersja jest strojona tak, aby po 12 turach różniły się m.in. liczba działających kolonii, populacja, handel, napięcie wojenne, siła piratów i zarobek kuriera.

`legacy_main.py` zawiera poprzednią prostszą wersję symulacji.
