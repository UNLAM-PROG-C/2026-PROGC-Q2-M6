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
  1: (("GOBLIN", 5),),
  2: (("GOBLIN", 8),),
  3: (("GOBLIN", 6), ("ORC", 2)),
  4: (("GOBLIN", 8), ("RUNNER", 3)),
  5: (("GOBLIN", 10), ("ORC", 4), ("RUNNER", 3)),
  6: (("GOBLIN", 12), ("ORC", 5), ("RUNNER", 4)),
  7: (("GOBLIN", 10), ("ORC", 4), ("RUNNER", 2), ("TROLL", 1)),
  8: (("GOBLIN", 12), ("ORC", 6), ("RUNNER", 4), ("TROLL", 2)),
  9: (("GOBLIN", 15), ("ORC", 8), ("RUNNER", 5), ("TROLL", 3)),
  10: (
    ("GOBLIN", 20),
    ("ORC", 10),
    ("RUNNER", 6),
    ("TROLL", 4),
    ("BOSS", 1),
  ),
}

TOWER_STATS = {
  "ARCHER": {"cost": 50, "damage": 10, "cooldown_seconds": 1.0},
  "CANNON": {"cost": 120, "damage": 40, "cooldown_seconds": 3.0},
  "MAGE": {"cost": 150, "damage": 15, "cooldown_seconds": 2.0},
}

ENEMY_STATS = {
  "GOBLIN": {"health": 30, "speed": "NORMAL", "reward": 5, "from_wave": 1},
  "ORC": {"health": 80, "speed": "SLOW", "reward": 10, "from_wave": 3},
  "RUNNER": {"health": 20, "speed": "FAST", "reward": 8, "from_wave": 4},
  "TROLL": {"health": 150, "speed": "SLOW", "reward": 20, "from_wave": 7},
  "BOSS": {"health": 500, "speed": "NORMAL", "reward": 100, "from_wave": 10},
}
