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
    children = [
      {Registry, keys: :duplicate, name: ThistleTea.PubSub},
      ThistleTea.DBC,
      ThistleTea.Mangos,
      {ThousandIsland,
       port: 3724, handler_module: ThistleTea.Auth, handler_options: @handler_options},
      {ThousandIsland,
       port: 8085, handler_module: ThistleTea.Game, handler_options: @handler_options}
    ]

    :ets.new(:session, [:named_table, :public])
    :ets.new(:guid_name, [:named_table, :public])
    setup_database()

    Logger.info("ThistleTea starting...")

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ThistleTea.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
