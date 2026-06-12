defmodule ThistleTea.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application

  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network.Server, as: GameServer
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ClassSpell, as: ClassSpellLoader
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Graveyard, as: GraveyardLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.GameEvent, as: GameEventSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Native.Namigator

  require Logger

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

  @env Mix.env()

  def setup_database do
    # in memory for now, so need to re-seed on startup
    ThistleTea.Account.init()
    ThistleTea.Account.register("pikdum", "pikdum")
    ThistleTea.Account.register("test", "test")

    Enum.each(1..10, fn i ->
      ThistleTea.Account.register("test#{i}", "test#{i}")
    end)

    Enum.each(0..999, fn i ->
      name = "BOT" <> String.pad_leading(Integer.to_string(i), 4, "0")
      ThistleTea.Account.register(name, name)
    end)
  end

  @impl true
  def start(_type, _args) do
    test = @env == :test

    children =
      [
        {Phoenix.PubSub, name: ThistleTea.PubSub},
        ThistleTea.Telemetry,
        GameEventSystem,
        PartySystem,
        {Group, name: Groups, log: false},
        EntityRegistry,
        AreaEffects,
        {Registry, keys: :duplicate, name: ThistleTea.ChatChannel},
        ThistleTea.DBC,
        Repo,
        !test &&
          {ThousandIsland, port: @auth_port, handler_module: ThistleTea.Auth, handler_options: @handler_options},
        !test &&
          {ThousandIsland, port: @game_port, handler_module: GameServer, handler_options: @handler_options},
        ThistleTeaWeb.Telemetry,
        !test && ThistleTeaWeb.Endpoint,
        {DynamicSupervisor, strategy: :one_for_one, name: EntitySupervisor, max_restarts: 1_000_000, max_seconds: 1},
        CellActivator
      ]
      |> Enum.filter(& &1)

    :ok = ThistleTeaWeb.Homography.init()

    :ets.new(:session, [:named_table, :public, read_concurrency: true, write_concurrency: :auto])
    Metadata.init()
    ItemLoader.init()
    ItemStore.init()
    CharacterStore.init()
    VendorLoader.init()
    QuestLoader.init()
    GossipLoader.init()
    CreatureTemplateLoader.init()
    GameObjectTemplateLoader.init()
    SpellLoader.init()
    TrainerLoader.init()
    ClassSpellLoader.init()
    LootLoader.init()
    GraveyardLoader.init()
    NpcTextLoader.init()
    :ets.new(:spline_counters, [:named_table, :public, write_concurrency: :auto])
    :ets.insert(:spline_counters, {:spline_id, 0})
    setup_database()
    SpatialHash.setup_tables()
    AggroProbe.init()
    ChaseWatch.init()

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

    :telemetry.attach(
      "mob-ai-tick-handler",
      [:thistle_tea, :mob, :ai_tick],
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

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      if !test do
        Logger.info("Loading quests...")
        QuestLoader.load_all()
        Logger.info("Loading gossip menus...")
        GossipLoader.load_all()
        Logger.info("Loading templates...")
        CreatureTemplateLoader.load_all()
        GameObjectTemplateLoader.load_all()
        Logger.info("Seeding debug data...")
        ThistleTea.DevSeed.run()
      end

      {:ok, pid}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ThistleTeaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
