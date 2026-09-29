defmodule ThistleTea.Game.World.Reaction do
  @moduledoc """
  Builds `Core.Combat.Hostility` reaction actors from guids, entity structs,
  and Metadata rows, and runs Hostility's checks over them.

  A guid becomes its Metadata row. An entity (anything with `object.guid`) keeps its own fresh
  unit, owner, pvp, and duel state on top of its published row, and a
  player-owned game object reacts with its owner's faction. Units controlled
  by another player get that player's projection under `:owner`, read once
  per actor.
  """
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.World.Metadata

  @actor_keys [
    :alive?,
    :feigning_death?,
    :faction_template,
    :faction_can_have_reputation?,
    :unit_flags,
    :reputation,
    :owner_guid,
    :pvp?,
    :free_for_all?,
    :group_id,
    :duel_started?,
    :duel_opponent_guid,
    :contested_pvp?,
    :proximity_aggro?
  ]

  @owner_keys [
    :level,
    :pvp?,
    :free_for_all?,
    :group_id,
    :duel_started?,
    :duel_opponent_guid,
    :contested_pvp?,
    :reputation
  ]

  def actor_keys, do: @actor_keys

  def actor(guid) when is_integer(guid), do: guid |> row() |> Map.put(:guid, guid) |> with_owner()

  def actor(%{object: %{guid: guid}} = entity) do
    entity
    |> Hostility.actor(projection(entity, guid))
    |> with_owner()
  end

  def actor(%{} = actor), do: with_owner(actor)
  def actor(_other), do: %{}

  def owner_projection(guid, metadata) when is_map(metadata) do
    metadata
    |> Map.put(:guid, guid)
    |> Hostility.owner_player()
    |> case do
      owner when is_integer(owner) -> Metadata.query(owner, @owner_keys) || %{}
      nil -> nil
    end
  end

  def owner_projection(_guid, _metadata), do: nil

  def hostile?(source, target), do: Hostility.hostile?(actor(source), actor(target))
  def friendly?(source, target), do: Hostility.friendly?(actor(source), actor(target))
  def reaction_rank(source, target), do: Hostility.reaction_rank(actor(source), actor(target))
  def neutral_to_all?(source), do: Hostility.neutral_to_all?(actor(source))
  def can_initiate_attack?(source), do: Hostility.can_initiate_attack?(actor(source))
  def valid_hostile_target?(source, target), do: Hostility.valid_hostile_target?(actor(source), actor(target))

  def valid_attack_target?(source, target, opts \\ []),
    do: Hostility.valid_attack_target?(actor(source), actor(target), opts)

  def can_attack_without_flagging?(source, target),
    do: Hostility.can_attack_without_flagging?(actor(source), actor(target))

  def attackable?(source, target), do: Hostility.attackable?(actor(source), actor(target))
  def can_assist?(source, target), do: Hostility.can_assist?(actor(source), actor(target))

  def targetable_by?(source, target, helpful? \\ false, opts \\ []),
    do: Hostility.targetable_by?(actor(source), actor(target), helpful?, opts)

  defp with_owner(%{owner: owner} = actor) when is_map(owner), do: actor

  defp with_owner(actor) do
    case Hostility.owner_player(actor) do
      owner when is_integer(owner) -> Map.put(actor, :owner, Metadata.query(owner, @owner_keys) || %{})
      nil -> actor
    end
  end

  defp projection(%{game_object: %{created_by: owner}}, guid) when is_integer(owner) and owner > 0 do
    guid
    |> row()
    |> Map.put(:faction_template, owner |> row() |> Map.get(:faction_template))
  end

  defp projection(_entity, guid), do: row(guid)

  defp row(guid), do: Metadata.query(guid, @actor_keys) || %{}
end
