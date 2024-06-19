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
    mob_ids = [
      79648,
      79651,
      79894,
      79900,
      79920,
      79928,
      79933,
      79934,
      79935,
      79936,
      79937,
      79938,
      79939,
      79940,
      79941,
      79945,
      79946,
      79954,
      79955,
      79957,
      79958,
      79959,
      79960,
      79974,
      79976,
      79977,
      79978,
      79979,
      79980,
      79981,
      79982,
      79983,
      79984,
      79985,
      79988,
      79990,
      80006,
      80007,
      80027,
      80135,
      80143,
      80157,
      80270,
      80341,
      80343
    ]

    mobs =
      Enum.map(mob_ids, fn id ->
        Supervisor.child_spec({ThistleTea.Mob, id}, id: id)
      end)

    children =
      [
        {Registry, keys: :unique, name: ThistleTea.Mobs},
        {Registry, keys: :duplicate, name: ThistleTea.PubSub},
        ThistleTea.DBC,
        ThistleTea.Mangos,
        {ThousandIsland,
         port: 3724, handler_module: ThistleTea.Auth, handler_options: @handler_options},
        {ThousandIsland,
         port: 8085, handler_module: ThistleTea.Game, handler_options: @handler_options}
      ] ++ mobs

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
