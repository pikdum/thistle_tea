defmodule ThistleTea.Game.Entity.EffectResolver.Pvp do
  @moduledoc """
  Resolves combat participants to their controlling players and snapshots the
  PvP facts needed by each owner. No other player's state is written here.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp, as: PvpLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata

  @fields [:owner_guid, :pvp?, :unit_flags, :free_for_all?, :contested_pvp?, :in_combat]

  def contacts(entity, source, target, role, opts \\ []) do
    get_metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, @fields))
    now = Keyword.get_lazy(opts, :now, &Time.now/0)
    source = profile(source, entity, get_metadata)
    target = profile(target, entity, get_metadata)
    effects = contact(source.player_guid, role, target, now)

    if role == :attack do
      source = %{source | pvp?: source.pvp? or (is_integer(source.player_guid) and target.pvp?)}
      effects ++ contact(target.player_guid, :attacked, source, now)
    else
      effects
    end
  end

  defp contact(player, role, %{pvp?: true, player_guid: other_player} = other, now)
       when is_integer(player) and player != other_player do
    [%Effects.PvpContact{target_guid: player, role: role, other: other, now: now}]
  end

  defp contact(_player, _role, _other, _now), do: []

  defp profile(guid, %Character{object: %{guid: guid}} = entity, _get_metadata) do
    %{
      player_guid: guid,
      pvp?: PvpLogic.active?(entity),
      free_for_all?: PvpLogic.free_for_all?(entity),
      contested_pvp?: PvpLogic.contested?(entity),
      in_combat: entity.internal.in_combat == true
    }
  end

  defp profile(guid, _entity, get_metadata) do
    metadata = if is_integer(guid), do: get_metadata.(guid) || %{}, else: %{}
    player = controlling_player(guid, metadata)
    owner = if is_integer(player) and player != guid, do: get_metadata.(player) || %{}, else: metadata

    %{
      player_guid: player,
      pvp?: Map.get(owner, :pvp?) == true or PvpLogic.active?(owner),
      free_for_all?: Map.get(owner, :free_for_all?) == true,
      contested_pvp?: Map.get(owner, :contested_pvp?) == true,
      in_combat: Map.get(owner, :in_combat) == true or Map.get(metadata, :in_combat) == true
    }
  end

  defp controlling_player(guid, metadata) do
    cond do
      player_guid?(guid) -> guid
      player_guid?(Map.get(metadata, :owner_guid)) -> metadata.owner_guid
      true -> nil
    end
  end

  defp player_guid?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false
end
