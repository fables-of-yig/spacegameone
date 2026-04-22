extends Node

# Cross-cutting runtime state the MV side needs to reach from any node —
# the current Main instance, the RoomManager handle, and the simulation
# pause flag that gates per-frame updates on projectiles, the player, and
# (eventually) enemies/triggers.
#
# Autoloaded as `MvGame`. Writes happen from MvMain on _ready / _exit_tree;
# reads happen from everywhere else.
#
# Mirrors the C# `Main.SimulationPaused` static flag + `Main.Instance`
# singleton in a way that doesn't require a class_name cycle between Main,
# RoomManager, and the projectile scripts.

var main: Node = null           # the MvMain instance while a planet is hosted
var room_manager: Node = null   # MvRoomManager handle (child of main)
var simulation_paused: bool = false
