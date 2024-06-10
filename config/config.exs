import Config

config :thistle_tea, ecto_repos: [ThistleTea.DBC, ThistleTea.Mangos]
config :thistle_tea, ThistleTea.DBC, database: "vanilla_dbcs.sqlite"
config :thistle_tea, ThistleTea.Mangos, database: "mangos0.sqlite"

config :mnesia, dir: ~c".mnesia/#{Mix.env()}/#{node()}"

import_config "#{config_env()}.exs"
