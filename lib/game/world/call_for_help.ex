defmodule ThistleTea.Game.World.CallForHelp do
  @moduledoc """
  Aggro chaining (vmangos CallAssistance / CallForHelp): finds eligible allied
  mobs near a mob that entered combat — or is being dragged from its spawn —
  and asks them to join the fight against its attacker.

  `assist/2` is the one-shot on-aggro scan (strict same-faction, fixed radius,
  fired after a reaction delay); `pulse/2` is the periodic in-combat scan
  (friendly factions, `call_for_help_range` radius). Both only recruit mobs
  whose faction template carries the respond-to-call-for-help flag; the
  recruited mob re-validates the target in its own process.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @assist_radius 10.0
  @assist_delay_ms 1_500
  @unit_flag_not_selectable 0x02000000

  def assist_delay_ms, do: @assist_delay_ms

  def assist(%Mob{} = state, target_guid) when is_integer(target_guid) and target_guid > 0 do
    notify_helpers(state, target_guid, @assist_radius, :same_faction)
  end

  def assist(_state, _target_guid), do: :ok

  def pulse(%Mob{internal: %Internal{creature: %Creature{call_for_help_range: range}}} = state, target_guid)
      when is_number(range) and range > 0 and is_integer(target_guid) and target_guid > 0 do
    notify_helpers(state, target_guid, range, :friendly)
  end

  def pulse(_state, _target_guid), do: :ok

  defp notify_helpers(%Mob{object: %{guid: caller_guid}} = state, target_guid, radius, faction_check) do
    case metadata_faction(caller_guid) do
      %FactionTemplate{} = caller_faction ->
        enemy_faction = metadata_faction(target_guid)

        state
        |> World.nearby_mobs(radius)
        |> Enum.each(&maybe_recruit(state, &1, target_guid, caller_faction, enemy_faction, faction_check))

      _ ->
        :ok
    end

    :ok
  end

  defp maybe_recruit(state, {helper_guid, _distance}, target_guid, caller_faction, enemy_faction, faction_check) do
    if eligible_helper?(helper_guid, caller_faction, enemy_faction, faction_check) and
         World.line_of_sight?(state, helper_guid) do
      Entity.assist_attack(helper_guid, target_guid)
    end
  end

  defp metadata_faction(guid) do
    case Metadata.query(guid, [:faction_template]) do
      %{faction_template: %FactionTemplate{} = faction_template} -> faction_template
      _ -> nil
    end
  end

  defp eligible_helper?(helper_guid, caller_faction, enemy_faction, faction_check) do
    helper_guid
    |> Metadata.query([:alive?, :faction_template, :unit_flags, :owner_guid])
    |> eligible_metadata?(caller_faction, enemy_faction, faction_check)
  end

  defp eligible_metadata?(
         %{alive?: true, faction_template: %FactionTemplate{} = helper_faction} = helper,
         caller_faction,
         enemy_faction,
         faction_check
       ) do
    Map.get(helper, :owner_guid) == nil and
      selectable?(Map.get(helper, :unit_flags)) and
      FactionTemplate.responds_to_call_for_help?(helper_faction) and
      allied?(helper_faction, caller_faction, faction_check) and
      not friendly_to_enemy?(helper_faction, enemy_faction)
  end

  defp eligible_metadata?(_helper, _caller_faction, _enemy_faction, _faction_check), do: false

  defp selectable?(flags) when is_integer(flags), do: (flags &&& @unit_flag_not_selectable) == 0
  defp selectable?(_flags), do: true

  defp allied?(%FactionTemplate{id: id}, %FactionTemplate{id: id}, _faction_check), do: true

  defp allied?(helper_faction, caller_faction, :friendly) do
    FactionTemplate.friendly_to?(helper_faction, caller_faction)
  end

  defp allied?(_helper_faction, _caller_faction, _faction_check), do: false

  defp friendly_to_enemy?(helper_faction, %FactionTemplate{} = enemy_faction) do
    FactionTemplate.friendly_to?(helper_faction, enemy_faction)
  end

  defp friendly_to_enemy?(_helper_faction, _enemy_faction), do: false
end
