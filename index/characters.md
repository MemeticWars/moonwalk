# Postacie i wspinanie

Agnes jest jedyną postacią tworzoną przez `moonwalk.gd`. Theia nie jest dostępna jako postać grywalna ani przez parametr uruchomienia; pliki historycznych modeli można zachować wyłącznie poza przepływem gry.

`human_controller.gd` zawiera wspólne stany ruchu, wspinania, pełzania i bezpiecznego wstawania. `humanoid_motion_library.gd` retargetuje dziesięć donorów animacji Agnes na model ze `Skeleton3D`, przy automatycznym rozpoznawaniu typowych nazw kości albo przez `humanoid_bone_map`.

Wspinanie nie zaczyna się na otworze drzwiowym: fasada musi być spójna na wysokości tułowia i po bokach, a głębokość trafień nie może wskazywać wnętrza. Na łuku Agnes pełza animacją `Crawl_and_Look_Back`, sprawdza podparcie w pięciu punktach i przy obu stopach, a po trwałym potwierdzeniu bezpiecznego dachu odtwarza `Stand_Up2`.

Testy: `godot/tests/crawl_roof_test.gd`, `godot/tests/human_motion_test.gd` i `godot/tests/human_actor_test.gd`; test wspinania na budynku uruchamia `--climb-test`.

## Historia błędów wspinaczki (2026-09-12): dlaczego same testy jednostkowe nie wystarczyły

Generalizacja wspinaczki przeszła syntetyczne testy jednostkowe, ale w realnej grze nie działała wcale — trzy osobne błędy, każdy widoczny dopiero na prawdziwej scenie, nie na pudełkach kolizji z testów:

1. `_solid_climb_patch()` wymagał zgodności głębi (≤0,35 m) między 9 promieniami na różnych wysokościach, żeby odrzucać drzwi. Prawdziwa fasada (cokół, opaski okienne) ma naturalną różnicę głębi ~0,4-0,5 m — próg odrzucał środek zwykłej ściany niemal wszędzie. Naprawa: odrzucanie drzwi przeniesione do `_doorway_ahead(direction)`, wywoływanego per-kierunek wewnątrz sweepu w `_nearest_climb_surface()`; `_solid_climb_patch()` sprawdza już tylko trafienie w litą, prawie pionową powierzchnię.
2. Cokoły (kolizja warstwy 1) wielu budynków Tycho były pojedynczym `BoxShape3D` = pełnym bounding boxem `dimensions[kind].size_m`. Trafne dla prostokątów, ale `l-shape-building` miał solidną kolizję we własnej brakującej ćwiartce, a `block-of-flats`/`central-building`/`central-house` to w rzeczywistości ośmiokąt / wydłużony wielokąt / rotunda ~50 m (nie bug skali importu — promień śladu central-house trzyma się 25,0-25,25 m przy 16 próbkowanych kątach) wpisane w dużo większy kwadrat, więc zasięg wspinaczki (1,7 m) prawie nigdzie nie trafiał w prawdziwą ścianę. Naprawa: `tycho_city.gd:_add_precise_footprint_collider` mierzy realny ślad budynku siatką promieni z góry na jego trimeshu i dopasowuje dwa pudełka dla L-kształtu (lustrzane dla `descriptor.mirror`) albo `ConvexPolygonShape3D`/`CylinderShape3D` z zmierzonych punktów obwodu.
3. `Stand_Up2` potrafił zapętlić się w nieskończoność stojąc na dachu, który realnie ją utrzymywał — `_physics_stand_up()` sprawdzał podparcie co klatkę na ŻYWEJ, aktualnie animowanej pozycji stóp; pojedyncza klatka wychylenia nogi poza krawędź cofała ją do pełzania i natychmiast uruchamiała animację od nowa. Naprawa: krótki okres łaski `STAND_UP_SUPPORT_GRACE` (0,25 s), ten sam wzorzec co `CLIMB_WALL_MISS_GRACE` przy oknach/drzwiach.

Namierzone dopiero przez `--climb-test` na realnym budynku ("twin-houses") i przez rzeczywisty playtest gotowej gry. Jeśli wspinanie/stanie na dachu znowu się zepsuje, podejrzewaj najpierw progi geometryczne wycechowane tylko na syntetycznych pudełkach oraz sprawdzenia stanu co klatkę bez debounce na żywej pozie animacji.
