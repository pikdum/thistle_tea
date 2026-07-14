import Config

alias ThistleTea.DB.Mangos.Repo

config :esbuild,
  version: "0.17.11",
  thistle_tea: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

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

config :phoenix, :json_library, Jason

config :tailwind,
  version: "4.3.2",
  thistle_tea: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :thistle_tea, Repo,
  database: "db/vmangos.sqlite",
  log: false,
  pool_size: 10,
  queue_target: 1_000,
  queue_interval: 5_000,
  busy_timeout: 5_000

config :thistle_tea, ThistleTea.DBC,
  database: "db/dbc.sqlite",
  log: false,
  pool_size: 20,
  queue_target: 1_000,
  queue_interval: 5_000,
  busy_timeout: 5_000

config :thistle_tea, ThistleTeaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThistleTeaWeb.ErrorHTML, json: ThistleTeaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ThistleTea.PubSub,
  live_view: [signing_salt: "TDSztxLy"]

config :thistle_tea, :map_dir, "maps"
config :thistle_tea, ecto_repos: [ThistleTea.DBC, Repo]

import_config "#{config_env()}.exs"
