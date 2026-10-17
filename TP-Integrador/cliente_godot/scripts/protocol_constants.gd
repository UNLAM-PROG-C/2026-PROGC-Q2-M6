extends Node
class_name ProtocolConstants

const DEFAULT_PORT: int = 5000

const HELLO: StringName = &"HELLO"
const READY: StringName = &"READY"
const BUY_TOWER: StringName = &"BUY_TOWER"
const SELL_TOWER: StringName = &"SELL_TOWER"
const PING: StringName = &"PING"

const WELCOME: StringName = &"WELCOME"
const STATE_UPDATE: StringName = &"STATE_UPDATE"
const WAVE_START: StringName = &"WAVE_START"
const BASE_DAMAGE: StringName = &"BASE_DAMAGE"
const GAME_OVER: StringName = &"GAME_OVER"
const ERROR: StringName = &"ERROR"

const CLIENT_MESSAGE_TYPES: Array[StringName] = [HELLO, READY, BUY_TOWER, SELL_TOWER, PING]
const SERVER_MESSAGE_TYPES: Array[StringName] = [WELCOME, STATE_UPDATE, WAVE_START, BASE_DAMAGE, GAME_OVER, ERROR]
