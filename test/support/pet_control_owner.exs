defmodule ThistleTea.Test.PetControlOwner do
  @moduledoc false
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl GenServer
  def init(options) do
    if guid = Keyword.get(options, :guid), do: Entity.register(guid)
    control = Keyword.get(options, :control, %Pet{owner_guid: 7})
    spells = Keyword.get(options, :spells, []) |> Map.new(&{&1.id, &1})
    {:ok, %Mob{unit: %Unit{health: 100}, internal: %Internal{pet: control, spellbook: spells}}}
  end

  @impl GenServer
  def handle_call(request, from, state), do: MobServer.handle_call(request, from, state)

  @impl GenServer
  def handle_info(_message, state), do: {:noreply, state}
end
