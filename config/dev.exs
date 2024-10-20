import Config
game_server = System.get_env("GAME_SERVER") || "localhost"
config :thistle_tea, :game_server, game_server
