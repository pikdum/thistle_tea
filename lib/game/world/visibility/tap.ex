defmodule ThistleTea.Game.World.Visibility.Tap do
  @moduledoc """
  Per-viewer dynamic-flag adjustment for mob updates: hides the gray tapped
  marker from the tapping player/group and the loot sparkle from players
  without loot rights, mirroring how mangos personalizes UNIT_DYNAMIC_FLAGS
  per recipient.
  """
  import Bitwise

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @dynamic_flag_lootable 0x0001
  @dynamic_flag_tapped 0x0004

  def personalize(%UpdateObject{unit: %{dynamic_flags: flags} = unit, object: %{guid: guid}} = update, viewer)
      when is_integer(flags) and (flags &&& (@dynamic_flag_tapped ||| @dynamic_flag_lootable)) != 0 and
             is_integer(viewer) do
    if Guid.entity_type(guid) == :mob do
      %{update | unit: %{unit | dynamic_flags: adjust(flags, guid, viewer)}}
    else
      update
    end
  end

  def personalize(update, _viewer), do: update

  defp adjust(flags, mob_guid, viewer) do
    meta = Metadata.query(mob_guid, [:tapped_player, :tapped_group_id, :assigned_looter]) || %{}
    tap_eligible? = tap_eligible?(meta, viewer)
    loot_eligible? = tap_eligible? and Map.get(meta, :assigned_looter) in [nil, viewer]

    flags
    |> clear_if(@dynamic_flag_tapped, tap_eligible?)
    |> clear_if(@dynamic_flag_lootable, not loot_eligible?)
  end

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
