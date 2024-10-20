import Config

config :thistle_tea, :game_server, System.get_env("GAME_SERVER", "localhost")
