"""Initial game balance and server configuration constants."""

SERVER_HOST = "0.0.0.0"
SERVER_PORT = 5000

INITIAL_GOLD = 200
INITIAL_BASE_HP = 100
BASE_DAMAGE_PER_ENEMY = 10
MAX_PLAYERS = 4
MIN_PLAYERS = 2
TOTAL_WAVES = 10
LANE_COUNT = 3
GAME_TICK_SECONDS = 0.05
SPAWN_INTERVAL_SECONDS = 0.05
CLIENT_SOCKET_TIMEOUT_SECONDS = 0.2
READY_BARRIER_TIMEOUT_SECONDS = 2.0
ENEMY_EXIT_POSITION = 100.0
ENEMY_SPEEDS = {
  "NORMAL": 10.0,
  "SLOW": 6.0,
  "FAST": 16.0,
}
WORKER_MODULE = "servidor.wave_worker"

WAVE_PATTERNS = {
  1: (("DISCOUNT_CHILD", 5),),
  2: (("DISCOUNT_CHILD", 8),),
  3: (("DISCOUNT_CHILD", 6), ("SHOPPING_GRANDMA", 2)),
  4: (("DISCOUNT_CHILD", 8), ("SKATEBOARD_CHILD", 3)),
  5: (("DISCOUNT_CHILD", 10), ("SHOPPING_GRANDMA", 4),
      ("SKATEBOARD_CHILD", 3)),
  6: (("DISCOUNT_CHILD", 12), ("SHOPPING_GRANDMA", 5),
      ("SKATEBOARD_CHILD", 4)),
  7: (("DISCOUNT_CHILD", 10), ("SHOPPING_GRANDMA", 4),
      ("SKATEBOARD_CHILD", 2), ("ARMORED_GRANDMA", 1)),
  8: (("DISCOUNT_CHILD", 12), ("SHOPPING_GRANDMA", 6),
      ("SKATEBOARD_CHILD", 4), ("ARMORED_GRANDMA", 2)),
  9: (("DISCOUNT_CHILD", 15), ("SHOPPING_GRANDMA", 8),
      ("SKATEBOARD_CHILD", 5), ("ARMORED_GRANDMA", 3)),
  10: (
    ("DISCOUNT_CHILD", 20),
    ("SHOPPING_GRANDMA", 10),
    ("SKATEBOARD_CHILD", 6),
    ("ARMORED_GRANDMA", 4),
    ("GOLD_CART_BOSS", 1),
  ),
}

TOWER_STATS = {
  "MOPPER": {
    "cost": 50, "damage": 10, "cooldown_seconds": 1.0,
    "special": "PUDDLE",
  },
  "STOCK_REPLENISHER": {
    "cost": 120, "damage": 40, "cooldown_seconds": 3.0,
    "special": "LINE_AREA",
  },
  "AUDIO_TOWER": {
    "cost": 150, "damage": 15, "cooldown_seconds": 2.0,
    "special": "SONIC_STUN",
    "stun_seconds": 0.5,
  },
}

ENEMY_STATS = {
  "DISCOUNT_CHILD": {
    "health": 30, "speed": "NORMAL", "reward": 5, "from_wave": 1,
  },
  "SHOPPING_GRANDMA": {
    "health": 80, "speed": "SLOW", "reward": 10, "from_wave": 3,
  },
  "SKATEBOARD_CHILD": {
    "health": 20, "speed": "FAST", "reward": 8, "from_wave": 4,
  },
  "ARMORED_GRANDMA": {
    "health": 150, "speed": "SLOW", "reward": 20, "from_wave": 7,
  },
  "GOLD_CART_BOSS": {
    "health": 500, "speed": "NORMAL", "reward": 100, "from_wave": 10,
  },
}
