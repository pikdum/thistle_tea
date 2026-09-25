defmodule ThistleTea.Game.World.CallForHelp do
  @moduledoc """
  Captures nearby helpers for delayed assistance and delivers immediate calls
  for help. Recipients revalidate their own eligibility before joining combat.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def assist_delay_ms, do: Assistance.delay_ms()

  def capture(%Mob{internal: %Internal{pet: nil, creature: %Creature{call_for_help_range: range}}} = state, target_guid)
      when is_number(range) and range > 0 do
    helpers(state, target_guid, Assistance.call_radius(), :same_faction)
  end

  def capture(_state, _target_guid), do: []

  def assist(%Mob{} = state, target_guid) when is_integer(target_guid) and target_guid > 0 do
    recruit(state, target_guid, capture(state, target_guid), :same_faction)
  end

  def assist(_state, _target_guid), do: :ok

  def deliver(%Mob{} = state, target_guid, helpers, source) do
    if state.internal.in_combat == true and state.unit.health > 0 and CombatLeash.reference(state) == source do
      recruit(state, target_guid, helpers, :same_faction)
    end

    :ok
  end

  def pulse(%Mob{internal: %Internal{creature: %Creature{call_for_help_range: range}}} = state, target_guid) do
    pulse(state, target_guid, range)
  end

  def pulse(_state, _target_guid), do: :ok

  def pulse(%Mob{} = state, target_guid, radius)
      when is_integer(target_guid) and target_guid > 0 and is_number(radius) and radius > 0 do
    recruit(state, target_guid, helpers(state, target_guid, radius, :friendly), :friendly)
  end

  def pulse(_state, _target_guid, _radius), do: :ok

  defp helpers(state, target_guid, radius, faction_check) do
    caller = Assistance.faction(Metadata.get(state.object.guid))
    enemy = Assistance.faction(Metadata.get(target_guid))

    state
    |> World.nearby_mobs(radius)
    |> Enum.flat_map(fn {guid, _distance} ->
      if guid != state.object.guid and not is_nil(reaction(Metadata.get(guid), caller, enemy, faction_check)) and
           World.line_of_sight?(state, guid), do: [guid], else: []
    end)
  end

  defp recruit(state, target_guid, helpers, faction_check) do
    caller = Assistance.faction(Metadata.get(state.object.guid))
    enemy = Assistance.faction(Metadata.get(target_guid))

    Enum.each(helpers, fn guid ->
      reaction = reaction(Metadata.get(guid), caller, enemy, faction_check)

      if same_world?(state, guid) and not is_nil(reaction) do
        notify_helper(state, guid, target_guid, faction_check, reaction)
      end
    end)

    :ok
  end

  defp reaction(helper, caller, enemy, check) do
    cond do
      Assistance.eligible?(helper, caller, enemy, check) -> :assist
      check == :friendly and Assistance.eligible_flee?(helper, caller, enemy) -> :flee
      true -> nil
    end
  end

  defp notify_helper(state, guid, target_guid, :same_faction, :assist),
    do: Entity.assist_attack(guid, target_guid, CombatLeash.reference(state))

  defp notify_helper(_state, guid, target_guid, :friendly, :assist), do: Entity.assist_attack(guid, target_guid)

  defp notify_helper(state, guid, target_guid, :friendly, :flee),
    do: Entity.flee_from_help(guid, state.object.guid, target_guid)

  defp same_world?(state, guid) do
    case World.position(guid) do
      {world, _, _, _} -> world == state.internal.world
      _ -> false
    end
  end
end
