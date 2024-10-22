import Config

config :thistle_tea, ThistleTeaWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "vEQPj+7/r5a1DKXk6/1z2IEEJQg/ToRMI//rC7ZDRWLUExIp2yXm7pSuEoIRp79F",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:thistle_tea, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:thistle_tea, ~w(--watch)]}
  ]

config :thistle_tea, BazWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/baz_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :thistle_tea, dev_routes: true

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
