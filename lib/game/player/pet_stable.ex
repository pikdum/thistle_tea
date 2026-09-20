defmodule ThistleTea.Game.Player.PetStable do
  @moduledoc """
  Stable-master interaction and owner-local pet transfers, including live snapshot and process cleanup.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Entity.Logic.PetStable, as: Stable
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.CreatureTemplate
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.StableSlotPrice
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Metadata

  @stablemaster_flag 0x00002000

  def list(%State{} = state, guid) do
    if authorized?(state, guid) do
      state = CompanionOwner.refresh(state)
      pets = Enum.map(Stable.entries(state.character), &listing/1)

      Network.send_packet(%Message.MsgListStabledPets{
        guid: guid,
        slots: state.character.internal.pet_stable.slots,
        pets: pets
      })

      state
    else
      result(state, :stable)
    end
  end

  def buy(%State{} = state, guid, opts \\ []) do
    lookup = Keyword.get(opts, :price_lookup, &StableSlotPrice.cost/1)

    if authorized?(state, guid) do
      case Stable.buy(state.character, lookup.(state.character.internal.pet_stable.slots + 1)) do
        {:ok, character} -> state |> commit(character) |> result(:bought)
        {:error, reason} -> result(state, reason)
      end
    else
      result(state, :stable)
    end
  end

  def transfer(%State{} = state, guid, operation, opts \\ []) do
    with true <- authorized?(state, guid),
         {:ok, planned} <- Stable.transfer(state.character, operation),
         {:ok, prepared} <- prepare_pet(planned, operation, opts) do
      finish_transfer(state, operation, prepared)
    else
      _ -> result(state, :stable)
    end
  end

  def authorized?(%State{ready: true, character: %Character{unit: %{class: 3}} = character}, guid) do
    with false <- Core.dead?(character) or character.internal.in_combat == true,
         :mob <- Guid.entity_type(guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(guid, [:alive?, :npc_flags]),
         true <- (flags &&& @stablemaster_flag) != 0,
         true <- Reputation.can_interact?(character, guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid) do
      true
    else
      _ -> false
    end
  end

  def authorized?(%State{}, _guid), do: false

  defp finish_transfer(state, operation, prepared) do
    state = state |> CompanionOwner.suspend() |> CompanionVisibility.clear()

    case Stable.transfer(state.character, operation) do
      {:ok, character} ->
        state
        |> commit(character)
        |> attach(prepared)
        |> result(if(operation == :store, do: :stored, else: :retrieved))

      {:error, reason} ->
        stop_prepared(prepared)
        result(state, reason)
    end
  end

  defp listing({slot, companion}) do
    entry =
      case companion.status do
        {:active, %EntityRef{entry: entry}} -> entry
        {:suspended, entry, _spell} -> entry
      end

    template = CreatureTemplate.get(entry)

    %{
      pet_number: companion.pet_number,
      entry: entry,
      level: companion.progress.level,
      name: template.name,
      loyalty: companion.progress.loyalty,
      slot: slot
    }
  end

  defp prepare_pet(_character, :store, _opts), do: {:ok, nil}

  defp prepare_pet(%Character{internal: %{companion: %{dead?: true}}}, _operation, _opts), do: {:ok, nil}

  defp prepare_pet(%Character{} = character, _operation, opts) do
    build = Keyword.get(opts, :build_pet, &Summon.build_pet/2)
    start = Keyword.get(opts, :start_pet, &MobLoader.start_mob/1)
    {:hunter_pet, entry, spell_id} = Companion.suspended(character)

    with %Mob{} = pet <- build.(entry, character),
         pet = %{pet | unit: %{pet.unit | created_by_spell: spell_id}},
         {:ok, pid} <- start.(pet) do
      {:ok, {pet, pid, spell_id}}
    else
      _ -> {:error, :stable}
    end
  end

  defp attach(%State{} = state, nil), do: state

  defp attach(%State{} = state, {%Mob{} = pet, pid, spell_id}) do
    attachment = %Attachment{
      kind: :hunter_pet,
      entity_ref: %EntityRef{guid: pet.object.guid, entry: Guid.entry(pet.object.guid), spell_id: spell_id},
      pid: pid,
      spells: Map.values(pet.internal.spellbook),
      progress: PetProgression.snapshot(pet)
    }

    state = CompanionOwner.attach(state, attachment)
    send(pid, {:attach_pet, self(), spell_id, attachment.spells})
    state
  end

  defp stop_prepared(nil), do: :ok
  defp stop_prepared({_pet, pid, _spell_id}), do: World.stop_entity(pid)

  defp commit(%State{} = state, %Character{} = character) do
    character = Core.mark_broadcast_update(character)
    CharacterStore.put(character)
    %{state | character: character}
  end

  defp result(state, reason) do
    code = %{money: 1, stable: 6, stored: 8, retrieved: 9, bought: 10}
    Network.send_packet(%Message.SmsgStableResult{result: Map.fetch!(code, reason)})
    state
  end
end
