defmodule ThistleTea.Game.Entity.Server.CreaturePetOwner do
  @moduledoc """
  Owns the monitored process edge of a creature's single combat-pet slot.
  Controlled summons require an empty slot. Summon-pet effects may replace a
  dead pet of the same entry.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.SummonedPet
  alias ThistleTea.Game.World.Metadata

  defmodule Monitor do
    @moduledoc false
    @enforce_keys [:token, :pid, :guid]
    defstruct [:token, :pid, :guid]
  end

  def summon(%Mob{object: %{guid: guid}} = owner, %Effects.SummonPet{source_guid: guid} = effect) do
    if not Core.dead?(owner) and not Corpse.removed?(owner) and available?(owner, effect.entry) do
      start_pet(owner, effect)
    else
      owner
    end
  end

  def summon(%Mob{object: %{guid: guid}} = owner, %Effects.SummonControlledPet{source_guid: guid} = effect) do
    if not Core.dead?(owner) and not Corpse.removed?(owner) and is_nil(Companion.active_ref(owner)) do
      start_pet(owner, effect)
    else
      owner
    end
  end

  def summon(%Mob{} = owner, _effect), do: owner

  defp start_pet(owner, effect) do
    pet = SummonedPet.build(owner, effect)
    owner = dismiss(owner)
    ref = %EntityRef{guid: pet.object.guid, entry: effect.entry, spell_id: effect.spell_id}
    owner = owner |> Companion.activate(:guardian, ref) |> publish()

    case MobLoader.start_mob(pet) do
      {:ok, pid} ->
        monitor = %Monitor{token: Process.monitor(pid), pid: pid, guid: ref.guid}
        %{owner | internal: %{owner.internal | companion_monitor: monitor}}

      _failed ->
        owner |> Companion.clear() |> publish()
    end
  end

  def process_down(%Mob{internal: %{companion_monitor: %Monitor{token: token}}} = owner, token) do
    owner = %{owner | internal: %{owner.internal | companion_monitor: nil}}
    owner |> Companion.removed(:process_down) |> publish()
  end

  def process_down(%Mob{} = owner, _token), do: owner

  def dismiss(%Mob{} = owner) do
    case owner.internal.companion_monitor do
      %Monitor{token: token} -> Process.demonitor(token, [:flush])
      nil -> :ok
    end

    if guid = Companion.active_guid(owner), do: World.stop_entity(guid)
    owner = %{owner | internal: %{owner.internal | companion_monitor: nil}}
    owner |> Companion.clear() |> publish()
  end

  def owner_stopped(%Mob{} = owner) do
    if guid = Companion.active_guid(owner), do: Task.start(fn -> World.stop_entity(guid) end)
    :ok
  end

  def defend(%Mob{} = owner, target) do
    with guid when is_integer(guid) <- Companion.active_guid(owner),
         pid when is_pid(pid) <- Entity.pid(guid) do
      send(pid, {:owner_attacked, target})
    end

    :ok
  end

  defp available?(owner, entry) do
    case Companion.active_ref(owner) do
      nil ->
        true

      %EntityRef{guid: guid, entry: current} ->
        not Entity.online?(guid) or (current == entry and match?(%{alive?: false}, Metadata.query(guid, [:alive?])))
    end
  end

  defp publish(owner) do
    Metadata.update(owner.object.guid, %{pet_guid: Companion.active_guid(owner)})
    Core.mark_broadcast_update(owner)
  end
end
