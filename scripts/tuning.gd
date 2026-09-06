class_name Tuning
extends RefCounted

# ВСЕ игровые числа живут здесь. Правь только этот файл при балансе.
# Значения подобраны на веб-прототипе, переведены в метры и секунды.

# --- Мир ---
const WORLD_SIZE := 140.0         # квадратная площадь WORLD_SIZE x WORLD_SIZE
const AGENT_COUNT := 500
const GRID_CELL := 4.0            # ячейка пространственного хеша

# --- Скорости (м/с) ---
# Заражённый МЕДЛЕННЕЕ бегущего горожанина, но не устаёт. Это ядро напряжения.
const CIV_WALK := 1.5
const CIV_PANIC := 4.2
const PLAYER_WALK := 2.1
const PLAYER_SPRINT := 4.6
const INFECTED_SPEED := 3.2
const COP_SPEED := 3.1
const INFECTED_COP_SPEED := 4.0

const ACCEL := 12.0               # сглаживание разгона
const KNOCKBACK_SPEED := 3.0      # рывок при срыве захвата (с потолком!)
const KNOCKBACK_DECAY := 6.0

# --- Заражение ---
const INCUBATION := 30.0          # секунд «скрытого» носителя
const GRAB_TIME := 1.4            # базовое время захвата
const GRAB_COP_MULT := 3.2        # мент держится втрое дольше
const GRAB_RANGE := 1.2           # радиус начала захвата
const GRAB_BREAK_RANGE := 2.6     # дальше этого — срыв
const RESIST_MIN := 0.75
const RESIST_MAX := 1.45

# --- Помощь толпы ---
const HELPER_RADIUS := 2.8
const HELPER_SLOW := 0.45         # каждый сосед замедляет захват
const HELPER_SHOVE_AT := 3        # столько соседей — оттаскивают
const HELPER_SHOVE_LOSS := 0.35   # сколько прогресса теряешь

# --- Паника ---
const PANIC_RADIUS := 6.0
const PANIC_MEMORY := 2.5

# --- Полиция ---
# Никакой телепатии: конус обзора + память + рация.
const COP_VIEW_DIST := 16.0
const COP_FOV_DEG := 100.0
const COP_MEMORY := 3.0           # помнит цель после потери
const COP_RADIO_RADIUS := 12.0    # передаёт тревогу соседям
const COP_SHOOT_RANGE := 7.0
const COP_SHOOT_CD := 1.1
const COP_ARREST_RANGE := 1.6     # схватит игрока при высоком подозрении
const ARREST_TIME      := 4.0     # секунд до провала ареста
const QTE_INTERVAL     := 0.75    # как часто меняется клавиша
const QTE_HIT_PROG     := 0.22    # прогресс за правильное нажатие (~5 нажатий)

# --- Подозрение (0..100) ---
const SUSP_DECAY := 1.2           # в секунду
const SUSP_SPRINT_NEAR := 2.0     # в секунду, когда бежишь у толпы
const SUSP_GRAB_FAIL := 9.0
const SUSP_GRAB_SEEN := 4.0
const SUSP_REVEAL := 1.3          # носитель вскрылся
const SUSP_COP_SPAWN := 28.0
const SUSP_HUNT_PLAYER := 65.0

const COP_MAX := 12
const COP_SPAWN_INTERVAL := 3.0

# --- Победа ---
const WIN_RATIO := 1.0

# --- QTE захвата и здоровье ---
const QTE_WRONG_LIMIT   := 2      # неверных нажатий до срыва захвата
const GRAB_QTE_INTERVAL := 2.5    # секунд на реакцию (истёк = промах)
const SUSP_QTE_FAIL     := 18.0   # подозрение при срыве через QTE
const AGENT_HEALTH      := 3      # выстрелов до смерти агента

# --- Бросок (ALT во время спринта) ---
const THROW_RANGE      := 7.0    # дальность броска (м)
const THROW_CD         := 5.0    # кулдаун броска (сек)
const THROW_START_PROG := 0.3    # стартовый прогресс QTE после броска

# --- Карта ---
# 4 блока × 20м + 5 улиц × 5м = 105 ≈ WORLD_SIZE; ox = -WORLD_SIZE/2 + MAP_STREET_W
const MAP_BLOCK_COLS := 5
const MAP_BLOCK_ROWS := 5
const MAP_BLOCK_SIZE := 20.0
const MAP_STREET_W   := 5.0
const MAP_SIDEWALK   := 1.5
const MAP_SEED       := 42
const MAP_PLAZA_FREQ := 7

# --- Этажи и ТЦ ---
const FLOOR_HEIGHT    := 3.5    # высота одного этажа (м)
const MALL_SIZE       := 48.0   # размер ТЦ по каждой оси
const MALL_FLOORS     := 4
const MALL_CLEARANCE  := 3.0    # свободный проход вокруг ТЦ
const MALL_AGENTS_PER_FLOOR := 50
const MALL_WALL_T     := 1.0    # толщина наружной стены ТЦ
const MALL_ENTRANCE_W := 6.0    # ширина входа (юг)
const FLOOR_CD        := 1.2    # кулдаун смены этажа (сек), чтоб не прыгали туда-обратно
const BUILDING_DOOR_W := 2.0    # ширина дверного проёма в обычных зданиях
const BUILDING_WALL_T := 0.5    # толщина стены здания

# --- Архетипы горожан ---
const ARCH_NORMAL     := 0
const ARCH_CHILD      := 1
const ARCH_ELDER      := 2
const ARCH_BRUTE      := 3
const ARCH_JOURNALIST := 4

# Порог прогресса QTE для заражения (NORMAL=5 нажатий, CHILD=2, ELDER=7, BRUTE=9, JOURNALIST=5)
const ARCH_THRESH     := [1.10, 0.44, 1.54, 1.98, 1.10]
# Множитель скорости паники к CIV_PANIC
const ARCH_PANIC_MULT := [1.0,  1.6,  0.65, 1.1,  1.0]
# Доля каждого архетипа (сумма = 1.0)
const ARCH_FREQ       := [0.60, 0.10, 0.15, 0.10, 0.05]

const JOURNALIST_PHOTO_TIME := 3.0   # сек до срабатывания фото
const SUSP_JOURNALIST       := 28.0  # подозрение от фото

# --- Эвакуация ---
const EVAC_SPOTS := [Vector2(0,-62),Vector2(62,0),Vector2(0,62),Vector2(-62,0)]
const EVAC_FIRST_TIME  := 60.0   # сек до первой точки эвакуации
const EVAC_INTERVAL    := 40.0   # сек между появлением новых точек
const EVAC_RADIUS      := 2.5    # радиус посадки в автобус
const EVAC_PULL_RANGE  := 30.0   # дальность притяжения к точке
const EVAC_PULL_SPEED  := 0.6    # скорость движения к эвакуации (м/с)
const EVAC_POINT_LIFE  := 35.0   # сек до отъезда автобуса
const EVAC_LOSE_AT     := 30     # поражение если столько убежало

# --- Мутации ---
const MUT_THRESHOLD       := 25
const MUT_SILENT_REVEAL   := 0
const MUT_FAST_INCUBATION := 1
const MUT_BACKSTAB        := 2
const MUT_WIDE_GRAB       := 3
const MUT_SILENT_SPRINT   := 4
const MUT_AUTO_GRAB       := 5
const MUT_CROWD_SPREAD    := 6

# --- Орда ---
const HORDE_CMD_DURATION := 15.0  # секунд работы команды
const HORDE_ARRIVE_DIST  := 3.0   # дистанция "прибыл к цели"

const MUT_NAMES := [
	"Тихое вскрытие",
	"Быстрая инкубация",
	"Атака сзади",
	"Широкий захват",
	"Бесшумный бег",
	"Автозахват",
	"Вирусная аура",
]
const MUT_DESC := [
	"Носители вскрываются без крика и паники толпы",
	"Инкубационный период: 30с → 6с",
	"Если жертва спиной — нужно всего 1 нажатие QTE",
	"Радиус начала захвата удвоен",
	"Спринт больше не повышает подозрение",
	"После успешного заражения сразу хватаешь ближайшего",
	"Заражённые передают инфекцию рядом стоящим без QTE (медленно)",
]

# --- Телефоны ---
const PHONE_FREQ        := 0.20   # доля горожан с телефоном
const PHONE_CALL_TIME   := 4.0    # секунд до звонка
const PHONE_COP_BONUS   := 2      # дополнительных копов при звонке
const SUSP_PHONE_CALL   := 22.0   # подозрение от звонка
const PHONE_PANIC_RANGE := 5.0    # видит панику в этом радиусе

# --- Эскалация ---
const ESC_THRESHOLDS  := [0.20, 0.40, 0.60]
const ESC_SPAWN_MULTS := [1.0,  0.6,  0.35]
const ESC_COP_MAXES   := [12,   18,   28]
const ESC_HEADLINE_DUR := 4.0
const ESC_HEADLINES_RU := [
	"ВЛАСТИ: \"СИТУАЦИЯ ПОД КОНТРОЛЕМ\"",
	"[!] ВВЕДЁН РЕЖИМ ЧРЕЗВЫЧАЙНОЙ СИТУАЦИИ [!]",
	"[!] АРМИЯ ВХОДИТ В ГОРОД [!]",
]

# --- Спецназ ---
const SWAT_SPEED        := 4.8
const SWAT_GRAB_MULT    := 5.0
const SWAT_THRESH_LEVEL := 2

# --- Visual animation (seconds and m/s; does not change simulation balance) ---
const ANIM_BLEND_TIME := 0.12
const ANIM_RUN_THRESHOLD := 2.5
const ANIM_ZOMBIE_RUN_THRESHOLD := 3.7
