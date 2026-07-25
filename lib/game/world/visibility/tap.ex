defmodule ThistleTea.Game.World.Visibility.Tap do
  @moduledoc """
  Per-viewer dynamic-flag adjustment for mob updates: hides the gray tapped
  marker from the tapping player/group and the loot sparkle from players
  without loot rights, mirroring how mangos personalizes UNIT_DYNAMIC_FLAGS
  per recipient.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Metadata

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
    meta = Metadata.query(mob_guid, [:tapped_player, :tapped_group_id, :loot_projection]) || %{}
    actor = ActorFactory.for_guid(viewer, mob_guid)
    tap_eligible? = LootSession.tap_allowed?(tap_policy(meta), actor)
    loot_eligible? = loot_visible?(meta, actor)

    flags
    |> clear_if(@dynamic_flag_tapped, tap_eligible?)
    |> clear_if(@dynamic_flag_lootable, not loot_eligible?)
  end

  defp tap_policy(%{loot_projection: projection}) when is_struct(projection, LootSession.Projection) do
    projection
  end

  defp tap_policy(meta) do
    %{tapped: %{player: Map.get(meta, :tapped_player), group_id: Map.get(meta, :tapped_group_id)}}
  end

  defp loot_visible?(%{loot_projection: projection}, actor) when is_struct(projection, LootSession.Projection),
    do: LootSession.visible?(projection, actor)

  defp loot_visible?(_meta, _actor), do: false

  defp clear_if(flags, bit, true), do: flags &&& bnot(bit)
  defp clear_if(flags, _bit, false), do: flags
end
