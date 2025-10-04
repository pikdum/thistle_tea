import Config

config :thistle_tea, :map_dir, "maps"
config :thistle_tea, ecto_repos: [ThistleTea.DBC, ThistleTea.DB.Mangos.Repo]
config :thistle_tea, ThistleTea.DBC, database: "db/dbc.sqlite", log: false
config :thistle_tea, ThistleTea.DB.Mangos.Repo, database: "db/mangos0.sqlite", log: false

config :mnesia, dir: ~c".mnesia/#{Mix.env()}/#{node()}"

config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [
    :username,
    :character_name,
    :target_name,
    :file,
    :pid,
    :mfa,
    :error_code
  ]

config :thistle_tea, ThistleTeaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThistleTeaWeb.ErrorHTML, json: ThistleTeaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ThistleTea.PubSub,
  live_view: [signing_salt: "TDSztxLy"]

config :esbuild,
  version: "0.17.11",
  thistle_tea: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  thistle_tea: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
