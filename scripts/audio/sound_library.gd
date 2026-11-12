class_name SoundLibrary
extends RefCounted
## Central sound catalog (Issue #53): music track id -> stream and sound event
## id -> variants and playback limits. Gameplay code plays sounds by id through
## the audio manager instead of loading streams or asset paths itself (like
## EffectLibrary for visuals). Sources, licences and the tracked/local-only file
## selection: assets/audio/README.md.
##
## Event fields (all optional except "streams"; missing ones use DEFAULTS):
##   "streams"    - Array of AudioStream variants; one is picked at random, never
##                  the same one twice in a row. Empty = no suitable sound yet:
##                  the event stays silent and must say why in "missing".
##   "volume_db"  - playback volume (on the SFX bus).
##   "pitch"      - random pitch spread (0.05 = 0.95-1.05).
##   "cooldown"   - seconds before this id can play again (requests in between are dropped).
##   "max_voices" - most simultaneous plays of this id.
##   "planned"    - true for events of objects that do not exist in the game yet
##                  (the next issue's room objects); registered so they need no new sounds.

const MUSIC_DIR := "res://assets/audio/Minifantasy_Dungeon_Music/Music/"
const DUNGEON := "res://assets/audio/Minifantasy_Dungeon_SFX/"
const MAGIC := "res://assets/audio/magic_spells_sfx_lite/wav/"

## Normal gameplay and Main Menu.
const MUSIC_NORMAL := &"normal"
## Miniboss and boss encounters.
const MUSIC_BATTLE := &"battle"

const MUSIC := {
	MUSIC_NORMAL: preload(MUSIC_DIR + "Goblins_Den_(Regular).wav"),
	MUSIC_BATTLE: preload(MUSIC_DIR + "Goblins_Dance_(Battle).wav"),
}

const DEFAULTS := {"volume_db": 0.0, "pitch": 0.05, "cooldown": 0.05, "max_voices": 4, "planned": false}

const EVENTS := {
	# --- Mage ---------------------------------------------------------------------
	## Fire Ball cast (every projectile; Twin Cast pairs collapse into one via the cooldown).
	&"mage_cast": {"streams": [preload(MAGIC + "fire_cast_01.wav")],
			"volume_db": -8.0, "pitch": 0.08, "cooldown": 0.06, "max_voices": 3},
	## Fire Ball hits an enemy or a wall.
	&"mage_spell_impact": {"streams": [preload(MAGIC + "fire_impact_01.wav")],
			"volume_db": -8.0, "pitch": 0.08, "cooldown": 0.05, "max_voices": 4},
	&"mage_hurt": {"streams": [preload(DUNGEON + "11_human_damage_1.wav"),
			preload(DUNGEON + "11_human_damage_2.wav"), preload(DUNGEON + "11_human_damage_3.wav")],
			"volume_db": -3.0, "cooldown": 0.2, "max_voices": 1},
	&"mage_death": {"streams": [preload(DUNGEON + "14_human_death_spin.wav")], "pitch": 0.0, "cooldown": 0.0, "max_voices": 1},
	&"mage_dash": {"streams": [preload(DUNGEON + "15_human_dash_1.wav"), preload(DUNGEON + "15_human_dash_2.wav")],
			"volume_db": -4.0, "cooldown": 0.1, "max_voices": 1},
	&"mage_level_up": {"streams": [preload(MAGIC + "ui/ui_magic_level_up_01.wav")], "volume_db": -6.0, "pitch": 0.0, "max_voices": 1},
	&"potion_health": {"streams": [preload(MAGIC + "heal_01.wav")], "volume_db": -6.0, "max_voices": 1},
	&"potion_speed": {"streams": [preload(MAGIC + "buff_01.wav")], "volume_db": -6.0, "max_voices": 1},
	&"home_teleport_cast": {"streams": [], "missing": "No channelling/charge sound that fits the Home Teleport cast."},
	&"home_teleport_complete": {"streams": [preload(MAGIC + "portal_01.wav")], "volume_db": -6.0, "max_voices": 1},
	&"seal_collected": {"streams": [preload(MAGIC + "rune_01.wav")], "volume_db": -4.0, "max_voices": 1},

	# --- Enemies ------------------------------------------------------------------
	&"enemy_hurt": {"streams": [], "missing": "No hurt sound for non-orc enemies (Demon, casters, minibosses, boss)."},
	&"enemy_death": {"streams": [], "missing": "No death sound for non-orc enemies (Demon, casters, minibosses, boss)."},
	&"enemy_contact_hit": {"streams": [], "missing": "No claw/bite sound for contact damage (Demon, Brood Mother)."},
	&"goblin_hurt": {"streams": [preload(DUNGEON + "21_orc_damage_1.wav"), preload(DUNGEON + "21_orc_damage_2.wav"),
			preload(DUNGEON + "21_orc_damage_3.wav")], "volume_db": -8.0, "cooldown": 0.25, "max_voices": 2},
	&"goblin_death": {"streams": [preload(DUNGEON + "24_orc_death_spin.wav")], "volume_db": -4.0, "cooldown": 0.1, "max_voices": 2},
	&"goblin_swing": {"streams": [preload(DUNGEON + "17_orc_atk_sword_1.wav"), preload(DUNGEON + "17_orc_atk_sword_2.wav"),
			preload(DUNGEON + "17_orc_atk_sword_3.wav")], "volume_db": -4.0, "cooldown": 0.1, "max_voices": 3},
	## Goblin special strike (lunge).
	&"goblin_special": {"streams": [preload(DUNGEON + "20_orc_special_atk.wav")], "volume_db": -3.0, "max_voices": 2},
	## Blood Monster charge windup.
	&"blood_monster_charge": {"streams": [preload(DUNGEON + "18_orc_charge.wav")], "volume_db": -4.0, "max_voices": 2},
	&"blood_blast_warning": {"streams": [], "missing": "No suitable warning sound (blood_cast_01 rejected, Issue #53)."},
	## Blood Monster death blast detonation.
	&"blood_blast": {"streams": [preload(MAGIC + "blood_impact_01.wav")], "volume_db": -3.0, "max_voices": 3},
	## Violet enemy bolts: Demon Caster, Hexcaller fan, Abyss Warden volley and ring.
	&"enemy_bolt_cast": {"streams": [preload(MAGIC + "void_cast_01.wav")],
			"volume_db": -10.0, "pitch": 0.1, "cooldown": 0.08, "max_voices": 3},
	&"enemy_bolt_impact": {"streams": [preload(MAGIC + "void_impact_01.wav")],
			"volume_db": -12.0, "pitch": 0.1, "cooldown": 0.08, "max_voices": 3},
	## Water Caster and Water Caster Boss bolts (launch; impact and bounce splash).
	&"water_bolt_cast": {"streams": [preload(MAGIC + "water_cast_01.wav")],
			"volume_db": -8.0, "pitch": 0.08, "cooldown": 0.08, "max_voices": 3},
	&"water_bolt_impact": {"streams": [preload(MAGIC + "water_impact_01.wav")],
			"volume_db": -8.0, "pitch": 0.08, "cooldown": 0.08, "max_voices": 3},

	# --- Minibosses and boss ------------------------------------------------------
	&"brood_summon": {"streams": [preload(MAGIC + "summon_01.wav")], "volume_db": -4.0, "max_voices": 1},
	&"brood_charge": {"streams": [], "missing": "No charge/roar sound that fits the Brood Mother."},
	&"hexcaller_hex": {"streams": [preload(MAGIC + "debuff_01.wav")], "volume_db": -6.0, "max_voices": 1},
	&"hexcaller_blink": {"streams": [preload(MAGIC + "teleport_01.wav")], "volume_db": -4.0, "max_voices": 1},
	## Water Caster Boss staggered water zones cast.
	&"water_boss_zones": {"streams": [preload(MAGIC + "water_cast_01.wav")], "volume_db": -6.0, "pitch": 0.0, "max_voices": 1},
	## Abyss Warden ground slam lands.
	&"boss_slam": {"streams": [preload(DUNGEON + "23_orc_jump_land.wav")], "volume_db": 0.0, "max_voices": 1},
	&"boss_phase": {"streams": [preload(MAGIC + "shadow_01.wav")], "volume_db": -3.0, "pitch": 0.0, "max_voices": 1},
	## Champion pack ward broken.
	&"champion_ward_broken": {"streams": [preload(MAGIC + "shield_break_01.wav")], "volume_db": -4.0, "max_voices": 1},

	# --- Room objects -------------------------------------------------------------
	&"chest_open": {"streams": [preload(DUNGEON + "01_chest_open_1.wav"), preload(DUNGEON + "01_chest_open_2.wav"),
			preload(DUNGEON + "01_chest_open_3.wav"), preload(DUNGEON + "01_chest_open_4.wav")], "max_voices": 2},
	&"chest_close": {"streams": [preload(DUNGEON + "02_chest_close_1.wav"), preload(DUNGEON + "02_chest_close_2.wav"),
			preload(DUNGEON + "02_chest_close_3.wav")], "max_voices": 2, "planned": true},
	&"crate_open": {"streams": [preload(DUNGEON + "03_crate_open_1.wav"), preload(DUNGEON + "03_crate_open_2.wav"),
			preload(DUNGEON + "03_crate_open_3.wav")], "max_voices": 2, "planned": true},
	&"sack_open": {"streams": [preload(DUNGEON + "04_sack_open_1.wav"), preload(DUNGEON + "04_sack_open_2.wav"),
			preload(DUNGEON + "04_sack_open_3.wav")], "max_voices": 2, "planned": true},
	## Room doors unlock when an encounter is cleared.
	&"door_open": {"streams": [preload(DUNGEON + "05_door_open_1.mp3"), preload(DUNGEON + "05_door_open_2.mp3")],
			"volume_db": -4.0, "cooldown": 0.2, "max_voices": 1},
	## Room doors lock when an encounter starts.
	&"door_close": {"streams": [preload(DUNGEON + "06_door_close_1.mp3"), preload(DUNGEON + "06_door_close_2.mp3")],
			"volume_db": -4.0, "cooldown": 0.2, "max_voices": 1},
	&"item_pickup": {"streams": [], "missing": "No pickup sound yet (gold, items, consumables)."},

	# --- UI -----------------------------------------------------------------------
	&"ui_click": {"streams": [], "missing": "No UI button sounds in the current packs."},
}


static func has(id: StringName) -> bool:
	return EVENTS.has(id)


## The event's variants, or [] if it is missing or unknown (unknown ids warn once per call).
static func streams(id: StringName) -> Array:
	if not EVENTS.has(id):
		push_warning("SoundLibrary: unknown sound event '%s'" % id)
		return []
	return EVENTS[id]["streams"]


## True for a registered event that has no suitable sound yet (plays silently).
static func is_missing(id: StringName) -> bool:
	return EVENTS.has(id) and (EVENTS[id]["streams"] as Array).is_empty()


## The event's `key` setting, else DEFAULTS[key].
static func setting(id: StringName, key: String) -> Variant:
	return EVENTS.get(id, {}).get(key, DEFAULTS.get(key))


static func missing_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in EVENTS:
		if is_missing(id):
			ids.append(id)
	return ids


## The music stream registered as `track`, or null if unknown.
static func music(track: StringName) -> AudioStream:
	return MUSIC.get(track)
