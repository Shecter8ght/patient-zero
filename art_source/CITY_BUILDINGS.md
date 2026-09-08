# Городские здания — вторая партия

Созданы 6 сентября 2026. Семейства: жилой дом `building_apartment_a`,
служебное здание `building_utility_a`, офис `building_office_a`.
После увеличения ТЦ в основной сцене 8 вариантов точных размеров:
3 жилых дома, 4 складских здания и 1 офис. Также осталось 3 одноэтажных дома.

У каждого нового здания отдельные Walls, Roof и Floor, по одной поверхности.
Материалы стен и крыши независимы между экземплярами. Крыша скрывается внутри,
стены затухают. Проём 2 м, этаж 3,5 м. Масштаб игровых экземпляров единичный,
окна фиксированного размера. Верхние этажи — фасад; интерьер на уровне земли.

Исходники: `blender/buildings/`. Экспорты: `../assets/models/buildings/`.
Состав и бюджеты: `city_buildings_manifest.json`.
Превью: `previews/city_buildings_godot.png`.

## Сборка

1. Godot: `--headless --path . --script res://art_source/export_building_layout.gd`
2. Blender: `--background --factory-startup --python art_source/build_city_buildings.py`
3. Godot: `--headless --editor --import --path .`
4. Godot: `--headless --path . --script res://art_source/check_city_buildings.gd`

Генератор создаёт три базовые модели, варианты под текущую карту и каталог
`scripts/city_building_catalog.gd` с preload для экспорта игры. При смене
размеров карты повторить сборку; до этого renderer использует процедурную
геометрию для несовпадающих размеров. Генератор перезаписывает свои файлы;
ручные варианты сохранять под отдельными именами.

Проверки: `city_check.log`, `city_preview.log`, `city_main.log`.
