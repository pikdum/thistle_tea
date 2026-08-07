defmodule ThistleTea.Game.Entity.Logic.Hostility do
  @moduledoc false

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  @unit_flag_non_attackable 0x00000002
  @unit_flag_non_attackable_2 0x00010000
  @unit_flag_not_selectable 0x02000000

  def hostile?(source, target) do
    source |> reaction_rank(target) |> rank_reaction() |> Kernel.==(:hostile)
  end

  def friendly?(source, target) do
    source |> reaction_rank(target) |> rank_reaction() |> Kernel.==(:friendly)
  end

  def reaction_rank(source, target) when is_integer(source) or is_integer(target) do
    reaction_rank(reaction_entity(source), reaction_entity(target))
  end

  def reaction_rank(source, target) do
    cond do
      same_controller?(source, target) ->
        :friendly

      duel_opponents?(source, target) ->
        :hostile

      true ->
        case reputation_reaction(source, target) do
          {:ok, rank} -> rank
          :none -> template_reaction_rank(source, target)
        end
    end
  end

  def neutral_to_all?(source) do
    source
    |> faction_template()
    |> FactionTemplate.neutral_to_all?()
  end

  def can_initiate_attack?(source) do
    alive?(source) and targetable?(source) and not neutral_to_all?(source)
  end

  def valid_hostile_target?(source, target) when is_integer(target) do
    target
    |> target_metadata()
    |> then(&valid_hostile_target?(source, &1))
  end

  def valid_hostile_target?(source, target) do
    alive?(target) and targetable?(target) and hostile?(source, target)
  end

  def valid_attack_target?(source, target) when is_integer(target) do
    target
    |> target_metadata()
    |> then(&valid_attack_target?(source, &1))
  end

  def valid_attack_target?(source, target) do
    alive?(target) and targetable?(target) and attack_reaction_allows?(source, target)
  end

  def attackable?(source, target) do
    valid_attack_target?(source, target)
  end

  def faction_template(%FactionTemplate{} = faction_template), do: faction_template
  def faction_template(%{faction_template: %FactionTemplate{} = faction_template}), do: faction_template

  def faction_template(%{object: %{guid: guid}}) when is_integer(guid) do
    case Metadata.query(guid, [:faction_template]) do
      %{faction_template: %FactionTemplate{} = faction_template} -> faction_template
      _ -> nil
    end
  end

  def faction_template(_source), do: nil

  defp template_reaction_rank(source, target) do
    with %FactionTemplate{} = source_template <- faction_template(source),
         %FactionTemplate{} = target_template <- faction_template(target) do
      cond do
        FactionTemplate.hostile_to?(source_template, target_template) -> :hostile
        FactionTemplate.friendly_to?(source_template, target_template) -> :friendly
        FactionTemplate.friendly_to?(target_template, source_template) -> :friendly
        true -> :neutral
      end
    else
      _ -> :neutral
    end
  end

  defp target_metadata(guid) when is_integer(guid) do
    case Metadata.query(guid, [
           :alive?,
           :faction_template,
           :faction_can_have_reputation?,
           :unit_flags,
           :reputation,
           :owner_guid,
           :contested_pvp?
         ]) do
      nil -> %{guid: guid}
      metadata -> Map.put(metadata, :guid, guid)
    end
  end

  defp reaction_entity(guid) when is_integer(guid), do: target_metadata(guid)
  defp reaction_entity(entity), do: entity

  defp attack_reaction_allows?(source, target) do
    cond do
      hostile?(source, target) or hostile?(target, source) -> true
      friendly?(source, target) or friendly?(target, source) -> false
      player_involved?(source, target) -> neutral_player_creature_attackable?(source, target)
      true -> false
    end
  end

  defp player_involved?(source, target) do
    player_controlled?(source) != player_controlled?(target)
  end

  defp neutral_player_creature_attackable?(source, target) do
    player = player_target(source, target)
    creature = non_player_target(source, target)

    forced_reaction?(player, creature) or not faction_can_have_reputation?(creature)
  end

  defp player_target(source, target) do
    if player_controlled?(source), do: source, else: target
  end

  defp non_player_target(source, target) do
    if player_controlled?(source), do: target, else: source
  end

  defp player_controlled?(entity) do
    player_guid?(guid(entity)) or player_guid?(owner_guid(entity))
  end

  defp duel_opponents?(source, target) do
    DuelSystem.active_opponents?(guid(source), guid(target))
  end

  defp owner_guid(%{owner_guid: owner_guid}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(%{internal: %{pet: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(_entity), do: nil

  defp player_guid?(guid) when is_integer(guid), do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false

  defp guid(%{guid: guid}) when is_integer(guid), do: guid
  defp guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  defp guid(_entity), do: nil

  defp faction_can_have_reputation?(%{faction_can_have_reputation?: can_have_reputation?})
       when is_boolean(can_have_reputation?) do
    can_have_reputation?
  end

  defp faction_can_have_reputation?(_entity), do: false

  defp reputation_reaction(source, target) do
    cond do
      player_controlled?(source) and not player_controlled?(target) ->
        player_reaction_to_creature(source, target)

      not player_controlled?(source) and player_controlled?(target) ->
        creature_reaction_to_player(source, target)

      true ->
        :none
    end
  end

  defp player_reaction_to_creature(player, creature) do
    faction_id = faction_id(creature)
    entry = reputation_entry(player, faction_id)

    cond do
      is_map(entry) and Map.has_key?(entry, :forced_rank) ->
        {:ok, entry.forced_rank}

      contested_guard_reaction?(creature, player) ->
        {:ok, :hostile}

      faction_can_have_reputation?(creature) and is_map(entry) ->
        {:ok, if(entry.at_war?, do: :hostile, else: :friendly)}

      true ->
        :none
    end
  end

  defp creature_reaction_to_player(creature, player) do
    faction_id = faction_id(creature)
    entry = reputation_entry(player, faction_id)

    cond do
      is_map(entry) and Map.has_key?(entry, :forced_rank) ->
        {:ok, entry.forced_rank}

      contested_guard_reaction?(creature, player) ->
        {:ok, :hostile}

      faction_can_have_reputation?(creature) and is_map(entry) ->
        {:ok, creature_player_rank(entry)}

      true ->
        :none
    end
  end

  defp creature_player_rank(%{at_war?: true, rank: rank}) when rank in [:friendly, :honored, :revered, :exalted],
    do: :neutral

  defp creature_player_rank(%{rank: rank}), do: rank

  defp contested_guard_reaction?(creature, player) do
    creature
    |> faction_template()
    |> FactionTemplate.attacks_contested_players?() and contested_pvp?(player)
  end

  defp contested_pvp?(%{contested_pvp?: contested_pvp?}) when is_boolean(contested_pvp?), do: contested_pvp?

  defp contested_pvp?(entity) do
    case player_owner_guid(entity) do
      guid when is_integer(guid) ->
        case Metadata.query(guid, [:contested_pvp?]) do
          %{contested_pvp?: contested_pvp?} when is_boolean(contested_pvp?) -> contested_pvp?
          _metadata -> false
        end

      _no_player ->
        false
    end
  end

  defp forced_reaction?(player, creature) do
    with faction_id when is_integer(faction_id) <- faction_id(creature),
         entry when is_map(entry) <- reputation_entry(player, faction_id) do
      Map.has_key?(entry, :forced_rank)
    else
      _ -> false
    end
  end

  defp reputation_entry(player, faction_id) do
    player
    |> reputation_projection()
    |> Map.get(faction_id)
  end

  defp reputation_projection(%{reputation: reputation}) when is_map(reputation), do: reputation

  defp reputation_projection(entity) do
    case player_owner_guid(entity) do
      guid when is_integer(guid) ->
        case Metadata.query(guid, [:reputation]) do
          %{reputation: reputation} when is_map(reputation) -> reputation
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp player_owner_guid(entity) do
    cond do
      player_guid?(guid(entity)) -> guid(entity)
      player_guid?(owner_guid(entity)) -> owner_guid(entity)
      true -> nil
    end
  end

  defp same_controller?(source, target) do
    source_owner = player_owner_guid(source)
    target_owner = player_owner_guid(target)
    is_integer(source_owner) and source_owner == target_owner
  end

  defp faction_id(entity) do
    case faction_template(entity) do
      %FactionTemplate{faction: faction_id} when faction_id > 0 -> faction_id
      _ -> nil
    end
  end

  defp rank_reaction(rank) when rank in [:hated, :hostile], do: :hostile
  defp rank_reaction(rank) when rank in [:friendly, :honored, :revered, :exalted], do: :friendly
  defp rank_reaction(_rank), do: :neutral

  defp alive?(%{alive?: false}), do: false
  defp alive?(%{unit: %Unit{}} = entity), do: not Core.dead?(entity)
  defp alive?(_target), do: true

  defp targetable?(%{unit_flags: flags}) when is_integer(flags), do: targetable_unit_flags?(flags)
  defp targetable?(%{unit: %Unit{flags: flags}}) when is_integer(flags), do: targetable_unit_flags?(flags)
  defp targetable?(_target), do: true

  defp targetable_unit_flags?(flags) when is_integer(flags) do
    (flags &&& (@unit_flag_non_attackable ||| @unit_flag_non_attackable_2 ||| @unit_flag_not_selectable)) == 0
  end
end
