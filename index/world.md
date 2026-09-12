# Świat gry: kurier InPost na Księżycu

## Fabularna przesłanka

Katastrofalna wojna na Ziemi odcięła księżycowe kolonie od macierzystych państw. Księżyc jest teraz podzielony między kilka frakcji o sprzecznych interesach: polskich górników, niemal samowystarczalne chińskie miasto, **Space Navy**, naukowców, miliarderów, piratów oraz ukrytą wspólnotę czczącą ocalały model AI (**Wspólnota Modelu**, jej **Świątynia Modelu** — patrz niżej).

Gracz gra kurierem InPost (`Siwy-04` w prototypie symulacji, patrz [design/lunar_inpost_strategy](../design/lunar_inpost_strategy/README.md)). Sieć InPost — łaziki, hoppery, satelity, magazyny, transport ludzi i towarów — utrzymuje przy życiu całą rozproszoną cywilizację, bo Księżyc jako całość produkuje prawie dość zasobów, żeby przeżyć, ale poszczególne kolonie są wyspecjalizowane i zależne od wymiany.

## Rozgrywka

Gracz wykonuje kursy między koloniami. Każda decyzja (dostawa zgodnie z kontraktem, samowolne przekierowanie ładunku, sprzedaż piratom, rezygnacja z kursu) wpływa na ceny, niedobory, relacje polityczne, bezpieczeństwo tras i przetrwanie poszczególnych społeczności. W tle toczy się strategiczna symulacja całego Księżyca (produkcja/konsumpcja kolonii, ataki piratów, rywalizacja **Space Navy–Blooming Flower**, napięcie w **Silesii**, ukryty rozwój Wspólnoty Modelu), ale gracz odwiedza tylko te regiony, do których faktycznie dociera jego kurier — sieć InPost ma za małą przepustowość, żeby uratować każdy kryzys, dlatego jeden kurs gracza na turę może zmienić wynik kampanii.

Z czasem zwykłe dostawy prowadzą gracza do tajnych transportów, konfliktów między mocarstwami i odkrycia ukrytej Świątyni Modelu.

**Świątynia Modelu nie jest publicznym węzłem mapy** — jej lokalizacji nie wolno zdradzać w dokumentacji ani w interfejsie gry; może zostać wykryta przez podejrzane transporty i późniejszą warstwę narracyjną.

## Stan implementacji

Ten opis to koncept narracyjny i ekonomiczny. Mechanicznie istnieje na razie tylko prototyp Pythonowy symulacji tur ([design/lunar_inpost_strategy/main.py](../design/lunar_inpost_strategy/main.py)) — nie jest jeszcze podłączony do gry w Godocie. Grywalna część projektu (patrz [index/project.md](project.md)) to na razie jeden sektor (Silesia) i postać Agnes bez frakcji, kontraktów ani ekonomii tur.
