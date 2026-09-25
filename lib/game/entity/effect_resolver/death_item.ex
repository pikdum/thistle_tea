defmodule ThistleTea.Game.Entity.EffectResolver.DeathItem do
  @moduledoc """
  Resolves death-item eligibility using the caster's current level and group.
  The original group tap survives changes to the tapping player's membership.
  """

  alias ThistleTea.Game.Entity.Logic.Aura.DeathItem
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground
  alias ThistleTea.Game.World.System.Party

  def resolve(%Effects.DeathItemReward{target_guid: caster} = reward, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:level]))

    with :player <- Guid.entity_type(caster),
         %{level: level} <- metadata.(caster),
         true <- DeathItem.eligible?(reward, level, tapped?(reward, opts)) do
      [%Effects.GiveItem{target_guid: caster, item_id: reward.item_id, count: reward.count, partial?: true}]
    else
      _ineligible -> []
    end
  end

  defp tapped?(%Effects.DeathItemReward{item_id: item}, _opts) when item != 6265, do: false
  defp tapped?(%Effects.DeathItemReward{victim: %{player?: true}}, _opts), do: false
  defp tapped?(%Effects.DeathItemReward{target_guid: guid, victim: %{tap: %{player: guid}}}, _opts), do: true

  defp tapped?(%Effects.DeathItemReward{target_guid: guid, victim: %{tap: tap}}, opts) do
    group_of = Keyword.get(opts, :group_of, &Party.group_of/1)
    same_group?(tap, group_of.(guid)) or battleground_member?(guid, opts)
  end

  defp same_group?(%{group_id: id}, %Group{id: id}) when not is_nil(id), do: true
  defp same_group?(_tap, _group), do: false

  defp battleground_member?(guid, opts) do
    position = Keyword.get(opts, :position, &World.position/1)
    participants = Keyword.get(opts, :participants, &Battleground.participants/1)

    case position.(guid) do
      {world, _x, _y, _z} -> Map.has_key?(participants.(world), guid)
      _missing -> false
    end
  end
end
