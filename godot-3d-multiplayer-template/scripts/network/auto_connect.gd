extends Node

func _ready():
    var mode = OS.get_environment("GODOT_AUTO_MODE")
    if mode == "server":
        print("Auto-connect: Starting server...")
        NetworkManager.host_game(load("res://scripts/network/network_connection_configs.gd").new("127.0.0.1"))
    elif mode == "client":
        print("Auto-connect: Connecting to server as client...")
        var config = load("res://scripts/network/network_connection_configs.gd").new("127.0.0.1")
        config.host_port = 8080
        NetworkManager.join_game(config)
