defmodule ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Companion

  @enforce_keys [:kind, :entity_ref, :pid, :spells]
  defstruct [:kind, :entity_ref, :pid, :spells, :create, :progress]

  @type t :: %__MODULE__{
          kind: Companion.kind(),
          entity_ref: Companion.EntityRef.t(),
          pid: pid(),
          spells: list(),
          create: term()
        }
end

defmodule ThistleTea.Game.Entity.Server.Player.CompanionOwner.Monitor do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Companion.EntityRef

  @enforce_keys [:token, :pid, :entity_ref]
  defstruct [:token, :pid, :entity_ref]

  @type t :: %__MODULE__{
          token: reference(),
          pid: pid(),
          entity_ref: EntityRef.t()
        }
end

defmodule ThistleTea.Game.Entity.Server.Player.CompanionOwner do
  @moduledoc """
  Owns the live process edge of a player's companion relationship.

  The character contains canonical domain state; this boundary stores only
  the monitor needed to observe process loss.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Logic.Companion, as: CompanionLogic
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Monitor
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World

  def attach(%State{} = state, %Attachment{pid: pid, entity_ref: %EntityRef{} = entity_ref} = attachment) do
    state = replace_previous(state, entity_ref.guid)
    monitor = monitor(state.companion_monitor, pid, entity_ref)

    character =
      state.character
      |> CompanionLogic.activate(attachment.kind, entity_ref)
      |> CompanionLogic.capture_progress(attachment.progress)

    %{state | character: character, companion_monitor: monitor}
  end

  def detach(%State{} = state, guid, reason) when is_integer(guid) do
    case state.companion_monitor do
      %Monitor{entity_ref: %EntityRef{guid: ^guid} = entity_ref} ->
        state = clear_monitor(state)
        character = CompanionLogic.removed(state.character, reason)
        {:ok, entity_ref, %{state | character: character}}

      _ ->
        :stale
    end
  end

  def process_down(%State{companion_monitor: %Monitor{token: token, entity_ref: entity_ref}} = state, token) do
    character = CompanionLogic.removed(state.character, :process_down)
    {:ok, entity_ref, %{state | character: character, companion_monitor: nil}}
  end

  def process_down(%State{}, _token), do: :stale

  def suspend(%State{character: %Character{}} = state) do
    case CompanionLogic.relationship(state.character) do
      %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}}
      when kind in [:hunter_pet, :guardian] ->
        state = clear_monitor(state)
        character = suspend_hunter_pet(state.character, guid)
        World.stop_entity(guid)
        %{state | character: CompanionLogic.suspend(character)}

      %Companion{status: {:active, %EntityRef{} = entity_ref}} ->
        state = clear_monitor(state)
        release_control(state.guid, entity_ref)
        %{state | character: CompanionLogic.clear(state.character)}

      _ ->
        clear_monitor(state)
    end
  end

  def suspend(%State{} = state), do: clear_monitor(state)

  def refresh(%State{character: %Character{} = character} = state) do
    case Entity.call(CompanionLogic.active_guid(character), :hunter_pet_snapshot) do
      {:ok, happiness, dead?, progress, reaction, health} ->
        character =
          character
          |> CompanionLogic.capture_happiness(happiness)
          |> CompanionLogic.capture_death(dead?)
          |> CompanionLogic.capture_progress(progress)
          |> CompanionLogic.capture_reaction(reaction)
          |> CompanionLogic.capture_health(health)

        %{state | character: character}

      _ ->
        state
    end
  end

  def suspend_hunter_pet(%Character{} = character, guid) do
    if CompanionLogic.entry(character) == Guid.entry(guid) do
      case Entity.call(guid, :suspend_hunter_pet) do
        {:ok, happiness, dead?, progress, reaction, health} when is_integer(happiness) ->
          character
          |> CompanionLogic.capture_happiness(happiness)
          |> CompanionLogic.capture_death(dead?)
          |> CompanionLogic.capture_progress(progress)
          |> CompanionLogic.capture_reaction(reaction)
          |> CompanionLogic.capture_health(health)

        {:error, :pet_broken} ->
          CompanionLogic.clear(character)

        _ ->
          character
      end
    else
      character
    end
  end

  def suspend_hunter_pet(entity, _guid), do: entity

  defp replace_previous(%State{} = state, next_guid) do
    case CompanionLogic.relationship(state.character) do
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
