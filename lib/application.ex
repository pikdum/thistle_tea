defmodule ThistleTea.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  # these are the defaults anyways
  @handler_options %{
    backlog: 1024,
    nodelay: true,
    send_timeout: 30_000,
    send_timeout_close: true,
    reuseaddr: true
  }

  @auth_port 3724
  @game_port 8085

  use Application

  require Logger

  def setup_database do
    # in memory for now, so need to re-seed on startup
    Memento.Table.create!(ThistleTea.Account)
    ThistleTea.Account.register("pikdum", "pikdum")
    ThistleTea.Account.register("test", "test")

    Enum.each(1..10, fn i ->
      ThistleTea.Account.register("test#{i}", "test#{i}")
    end)

    Memento.Table.create!(ThistleTea.Character)
  end

  @impl true
  def start(_type, _args) do
    children =
      [
        ThistleTea.Telemetry,
        {Registry, keys: :duplicate, name: ThistleTea.ChatChannel},
        ThistleTea.DBC,
        ThistleTea.Mangos,
        ThistleTea.MobSupervisor,
        ThistleTea.GameObjectSupervisor,
        {ThousandIsland,
         port: @auth_port, handler_module: ThistleTea.Auth, handler_options: @handler_options},
        {ThousandIsland,
         port: @game_port, handler_module: ThistleTea.Game, handler_options: @handler_options},
        ThistleTeaWeb.Telemetry,
        {Phoenix.PubSub, name: ThistleTea.PubSub},
        ThistleTeaWeb.Endpoint
      ]

    :ets.new(:session, [:named_table, :public])
    :ets.new(:guid_name, [:named_table, :public])
    setup_database()
    SpatialHash.setup_tables()

    :telemetry.attach(
      "handle-packet-handler",
      [:thistle_tea, :handle_packet, :stop],
      &ThistleTea.Telemetry.handle_event/4,
      nil
    )

    :telemetry.attach(
      "mob-wake-up-handler",
      [:thistle_tea, :mob, :wake_up],
      &ThistleTea.Telemetry.handle_event/4,
      nil
    )

    :telemetry.attach(
      "mob-try-sleep-handler",
      [:thistle_tea, :mob, :try_sleep],
      &ThistleTea.Telemetry.handle_event/4,
      nil
    )

    Logger.info("Loading maps...")
    map_dir = Application.fetch_env!(:thistle_tea, :map_dir)
    Namigator.load(map_dir)

    Logger.info("ThistleTea started.")

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ThistleTea.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ThistleTeaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
