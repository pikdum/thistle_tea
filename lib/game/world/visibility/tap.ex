defmodule ThistleTea.Game.World.Visibility.Tap do
  @moduledoc """
  Per-viewer dynamic-flag adjustment for mob updates: hides the gray tapped
  marker from the tapping player/group and the loot sparkle from players
  without loot rights or without anything they can actually take, mirroring
  how mangos personalizes UNIT_DYNAMIC_FLAGS per recipient.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @dynamic_flag_lootable 0x0001
  @dynamic_flag_tapped 0x0004

  def personalize(
        %UpdateObject{unit: %{dynamic_flags: flags} = unit, object: %{guid: guid}} = update,
        viewer,
        character
      )
      when is_integer(flags) and (flags &&& (@dynamic_flag_tapped ||| @dynamic_flag_lootable)) != 0 and
             is_integer(viewer) do
    if Guid.entity_type(guid) == :mob do
      %{update | unit: %{unit | dynamic_flags: adjust(flags, guid, viewer, character)}}
    else
      update
    end
  end

  def personalize(update, _viewer, _character), do: update

  defp adjust(flags, mob_guid, viewer, character) do
    meta = Metadata.query(mob_guid, [:tapped_player, :tapped_group_id, :assigned_looter, :loot_summary]) || %{}
    tap_eligible? = tap_eligible?(meta, viewer)

    loot_eligible? =
      tap_eligible? and Map.get(meta, :assigned_looter) in [nil, viewer] and
        takeable?(Map.get(meta, :loot_summary), character)

    flags
    |> clear_if(@dynamic_flag_tapped, tap_eligible?)
    |> clear_if(@dynamic_flag_lootable, not loot_eligible?)
  end

  defp takeable?(%{gold?: true}, _character), do: true
  defp takeable?(%{general_items?: true}, _character), do: true

  defp takeable?(%{quest_item_ids: [_ | _] = item_ids}, %Character{} = character) do
    Enum.any?(item_ids, &Quests.needs_item?(character, &1))
  end

  defp takeable?(%{quest_item_ids: [_ | _]}, _character), do: true
  defp takeable?(%{gold?: false, general_items?: false, quest_item_ids: []}, _character), do: false
  defp takeable?(_summary, _character), do: true

  defp tap_eligible?(meta, viewer) do
    cond do
      Map.get(meta, :tapped_player) in [nil, viewer] -> true
      is_integer(Map.get(meta, :tapped_group_id)) -> viewer_in_group?(viewer, meta.tapped_group_id)
      true -> false
    end
  end

  defp viewer_in_group?(viewer, group_id) do
    case PartySystem.group_of(viewer) do
      %Party.Group{id: ^group_id} -> true
      _ -> false
    end
  end

  defp clear_if(flags, bit, true), do: flags &&& bnot(bit)
  defp clear_if(flags, _bit, false), do: flags
end
