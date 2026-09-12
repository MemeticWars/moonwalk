# GeoServer → Moonwalk

Adapter i klient są zaimplementowane. Przykładowa konfiguracja nie wskazuje istniejących warstw; serwer danych nie został automatycznie wdrożony. Prototyp Godota pozostaje grywalny offline.

## Publikacja danych

1. Przygotuj zarejestrowane przestrzennie DEM i ortofoto dla konkretnego sektora. Dla DEM zachowaj dane liczbowe i metry. Braki oznacz jako NoData; nie udawaj, że czarne obszary ortofoto to pomiar wysokości.
2. Dodaj wymagane księżycowe CRS do `GEOSERVER_DATA_DIR/user_projections/epsg.properties`; przykłady są w tym repozytorium. Zrestartuj GeoServer i sprawdź rozpoznawanie układu. Kody 100001/100002 są lokalnymi identyfikatorami przykładu.
3. Utwórz workspace `moon`, magazyny GeoTIFF lub ImageMosaic i warstwy DEM/ortofoto. Nadaj im natywny CRS odpowiadający rzeczywistym danym; w razie potrzeby wcześniej wykonaj reprojekcję. Włącz WCS 1.0.0 i WMS 1.1.1.
4. Sprawdź `GetCapabilities` i `DescribeCoverage` w GeoServerze. Testowy wycinek WCS powinien zwrócić 35×35 pojedynczych próbek, ze wspólnymi krawędziami sąsiadujących kafli. Dla WMS ustaw styl pokazujący obraz, bez siatki, podpisów i automatycznych legend.

## Konfiguracja adaptera

Skopiuj `geoserver.example.json` do `geoserver.local.json`. Ustaw `geoserver_url`, `dem_layer`, `ortho_layer`, `crs`, `origin_easting_m`, `origin_northing_m`, `reference_elevation_m` i zakres indeksów kafli. Origin to punkt odpowiadający (X=0, Z=0) w grze. Wysokości w odpowiedzi są pomniejszone o wysokość odniesienia. W razie potrzeby ustaw skalę i offset źródła, np. dla LOLA w półmetrach. Zmiana danych wymaga nowego `revision`.

Instalacja zależności i start:

```powershell
python -m pip install -r services/requirements.txt
python services/terrain_gateway.py --config services/geoserver.local.json
```

Serwer nasłuchuje lokalnie na `127.0.0.1:8787`. `GET /health` testuje działanie adaptera, nie dostępność źródłowego GeoServera. Pakiet kafla: `GET /v1/silesia-v1/silesia/0/0.json`. Dla wdrożenia publicznego adapter powinien działać za standardowym reverse proxy z HTTPS; adres GeoServera i uprawnienia administracyjne pozostają poza klientem gry.

W `godot/terrain_server.cfg` ustaw `enabled=true`, URL adaptera, ten sam `revision` i `sector`. Restart gry przełączy źródło na cache/HTTP. Cache klienta znajduje się w katalogu danych użytkownika Godota pod `terrain`. Nowe dane są walidowane przed zapisem; brak sieci i odpowiedzi 404/502 nie blokują gry.

Adapter ogranicza równoległe zapytania do GeoServera do dwóch, odrzuca nieznane sektory i wyjście poza zakres, kontroluje rozmiar odpowiedzi i wartości wysokości. Serwerowy cache jest zależny od wersji oraz konfiguracji. Obsługa sekretnej lokacji wymaga później autoryzowanego katalogu sektorów — samo ukrycie etykiety na globie nie chroni zasobów publicznego serwera.

## Sprawdzenie bez własnego GeoServera

```powershell
python -m unittest discover -s services -v
python services/verify_godot_client.py
```

Drugi test uruchamia lokalny adapter z analitycznym rastrem zamiast zewnętrznego WCS, a następnie prawdziwego klienta Godota. Sprawdza HTTP, float32, cache, wersjonowanie i brakujące pokrycie. **Nie zastępuje testu reprojekcji i georeferencji prawdziwych warstw GeoServera.**

Implementacja prototypowa generuje kafle na żądanie. Przed udostępnieniem większej gry warto wypiec najczęstsze trasy i sektory do statycznego cache/CDN, przygotować pobieranie startowego obszaru przed lądowaniem, blending granic danych i mechanizm zmiany sektora.
