defmodule ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment do
  @moduledoc false

  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PetName
  alias ThistleTea.Game.Core.Pet.PetProgression
  alias ThistleTea.Game.Network.Message.SmsgPetNameQueryResponse
  alias ThistleTea.Game.Network.UpdateObject

  @enforce_keys [:kind, :entity_ref, :pid, :spells]
  defstruct [:kind, :entity_ref, :pid, :spells, :create, :progress, :name, :name_response, restore_automatically?: true]

  @type t :: %__MODULE__{
          kind: Companion.kind(),
          entity_ref: Companion.EntityRef.t(),
          pid: pid(),
          spells: list(),
          create: term(),
          name: PetName.t() | nil,
          name_response: %SmsgPetNameQueryResponse{} | nil,
          restore_automatically?: boolean()
        }

  def from_pet(%Mob{internal: %{pet: %Pet{} = pet}} = entity, pid, spell_id, spells \\ nil) do
    %__MODULE__{
      kind: companion_kind(pet),
      entity_ref: %EntityRef{guid: entity.object.guid, entry: entity.object.entry, spell_id: spell_id},
      pid: pid,
      spells: spells || Map.values(entity.internal.spellbook || %{}),
      create: UpdateObject.from_entity(entity),
      progress: PetProgression.snapshot(entity),
      restore_automatically?: restore_automatically?(entity.internal.spawn),
      name: summoned_name(entity),
      name_response: SmsgPetNameQueryResponse.for_pet(entity)
    }
  end

  defp summoned_name(%Mob{internal: %{pet: %Pet{kind: :summon}, name: name}, unit: unit}) when is_binary(name),
    do: %PetName{name: name, timestamp: unit.pet_name_timestamp || 0}

  defp summoned_name(_entity), do: nil

  defp restore_automatically?(%Spawn{despawn_delay_ms: delay}) when is_integer(delay) and delay > 0, do: false
  defp restore_automatically?(_spawn), do: true

  defp companion_kind(%Pet{kind: :hunter}), do: :hunter_pet
  defp companion_kind(%Pet{kind: :possessed}), do: :possession
  defp companion_kind(%Pet{kind: :charmed}), do: :charm
  defp companion_kind(%Pet{}), do: :guardian
end

defmodule ThistleTea.Game.World.Entity.Player.CompanionOwner.Monitor do
  @moduledoc false

  alias ThistleTea.Game.Core.Pet.Companion.EntityRef

  @enforce_keys [:token, :pid, :entity_ref]
  defstruct [:token, :pid, :entity_ref]

  @type t :: %__MODULE__{
          token: reference(),
          pid: pid(),
          entity_ref: EntityRef.t()
        }
end

defmodule ThistleTea.Game.World.Entity.Player.CompanionOwner do
  @moduledoc """
  Owns the live process edge of a player's companion relationship.

  The character contains canonical domain state; this boundary stores only
  the monitor needed to observe process loss.
  """

  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PetName
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Monitor
  alias ThistleTea.Game.World.Entity.Player.CompanionVisibility
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.SummonedPet

  def summon(
        %State{character: %Character{object: %{guid: guid}} = character},
        %Effects.SummonControlledPet{source_guid: guid} = effect
      ) do
    if Death.alive?(character) and is_nil(Companion.active_ref(character)) do
      pet = SummonedPet.build(character, effect)

      case MobLoader.start_mob(pet) do
        {:ok, pid} -> Attachment.from_pet(pet, pid, effect.spell_id)
        _failed -> nil
      end
    end
  end

  def summon(%State{}, _effect), do: nil

  def attach(%State{} = state, %Attachment{pid: pid, entity_ref: %EntityRef{} = entity_ref} = attachment) do
    state = replace_previous(state, entity_ref.guid)
    monitor = monitor(state.companion_monitor, pid, entity_ref)

    character =
      state.character
      |> Companion.activate(attachment.kind, entity_ref)
      |> Companion.capture_progress(attachment.progress)
      |> Companion.set_automatic_restore(attachment.restore_automatically?)
      |> remember_name(entity_ref.guid, attachment.name)

    %{state | character: character, companion_monitor: monitor}
  end

  def detach(%State{} = state, guid, :released) when is_integer(guid) do
    if Companion.control_guid(state.character) == guid, do: detach_current(state, guid, :released), else: :stale
  end

  def detach(%State{} = state, guid, reason) when is_integer(guid), do: detach_current(state, guid, reason)

  defp detach_current(%State{} = state, guid, reason) do
    case state.companion_monitor do
      %Monitor{entity_ref: %EntityRef{guid: ^guid} = entity_ref} = monitor ->
        character = Companion.removed(state.character, reason)
        state = %{state | character: character}

        state =
          case Companion.active_ref(character) do
            %EntityRef{guid: ^guid} = retained -> %{state | companion_monitor: %{monitor | entity_ref: retained}}
            _ -> clear_monitor(state)
          end

        {:ok, entity_ref, state}

      _ ->
        :stale
    end
  end

  def process_down(%State{companion_monitor: %Monitor{token: token, entity_ref: entity_ref}} = state, token) do
    character = Companion.removed(state.character, :process_down)
    {:ok, entity_ref, %{state | character: character, companion_monitor: nil}}
  end

  def process_down(%State{}, _token), do: :stale

  def suspend(%State{character: %Character{}} = state) do
    state = CompanionVisibility.release_control(state, Companion.possession_guid(state.character))

    case Companion.relationship(state.character) do
      %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}}
      when kind in [:hunter_pet, :guardian] ->
        state = clear_monitor(state)
        character = suspend_hunter_pet(state.character, guid)
        World.stop_entity(guid)
        %{state | character: Companion.suspend(character)}

      %Companion{status: {:active, %EntityRef{} = entity_ref}} ->
        state = clear_monitor(state)
        release_control(state.guid, entity_ref)
        %{state | character: Companion.clear(state.character)}

      _ ->
        clear_monitor(state)
    end
  end

  def suspend(%State{} = state), do: clear_monitor(state)

  def refresh(%State{character: %Character{internal: %{companion: %{kind: :hunter_pet}}} = character} = state) do
    case Entity.call(Companion.active_guid(character), :hunter_pet_snapshot) do
      {:ok, happiness, dead?, progress, reaction, health} ->
        character =
          character
          |> Companion.capture_happiness(happiness)
          |> Companion.capture_death(dead?)
          |> Companion.capture_progress(progress)
          |> Companion.capture_reaction(reaction)
          |> Companion.capture_health(health)

        %{state | character: character}

      _ ->
        state
    end
  end

  def refresh(%State{} = state), do: state

  def suspend_hunter_pet(%Character{} = character, guid) do
    if Companion.entry(character) == Guid.entry(guid) do
      case Entity.call(guid, :suspend_hunter_pet) do
        {:ok, happiness, dead?, progress, reaction, health} when is_integer(happiness) ->
          character
          |> Companion.capture_happiness(happiness)
          |> Companion.capture_death(dead?)
          |> Companion.capture_progress(progress)
          |> Companion.capture_reaction(reaction)
          |> Companion.capture_health(health)

        {:error, :pet_broken} ->
          Companion.clear(character)

        _ ->
          character
      end
    else
      character
    end
  end

  def suspend_hunter_pet(entity, _guid), do: entity

  defp remember_name(character, _guid, nil), do: character
  defp remember_name(character, guid, %PetName{} = name), do: Companion.remember_name(character, guid, name)

  defp replace_previous(%State{} = state, next_guid) do
    case Companion.relationship(state.character) do
      %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}}
      when guid != next_guid and kind in [:hunter_pet, :guardian] ->
        state = clear_monitor(state)
        World.stop_entity(guid)
        state

      %Companion{status: {:active, %EntityRef{guid: guid} = entity_ref}} when guid != next_guid ->
        state = clear_monitor(state)
        release_control(state.guid, entity_ref)
        state

      _ ->
        state
    end
  end

  defp monitor(%Monitor{pid: pid, entity_ref: %EntityRef{guid: guid}} = monitor, pid, %EntityRef{guid: guid}) do
    monitor
  end

  defp monitor(%Monitor{} = monitor, pid, %EntityRef{} = entity_ref) do
    Process.demonitor(monitor.token, [:flush])
    %Monitor{token: Process.monitor(pid), pid: pid, entity_ref: entity_ref}
  end

  defp monitor(nil, pid, %EntityRef{} = entity_ref) do
    %Monitor{token: Process.monitor(pid), pid: pid, entity_ref: entity_ref}
  end

  defp clear_monitor(%State{companion_monitor: %Monitor{token: token}} = state) do
    Process.demonitor(token, [:flush])
    %{state | companion_monitor: nil}
  end

  defp clear_monitor(%State{} = state), do: state

  defp release_control(owner_guid, %EntityRef{} = entity_ref) do
    case Entity.pid(entity_ref.guid) do
      pid when is_pid(pid) -> send(pid, {:release_control, owner_guid, entity_ref.spell_id})
      _ -> :ok
    end
  end
end
