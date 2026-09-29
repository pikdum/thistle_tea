defmodule ThistleTea.Game.Core.Combat.Hostility do
  @moduledoc """
  Unit reactions and attack/assist eligibility after vmangos
  `Unit::GetReactionTo`, `IsValidAttackTarget`, and `IsValidAssistTarget`.

  Every argument is a reaction actor: a plain map shaped like a
  `World.Metadata` row (`:guid`, `:faction_template`, `:unit_flags`,
  `:owner_guid`, pvp, duel, group, and reputation fields). A unit controlled
  by another player carries that player's projection under `:owner`. Build
  actors from entity structs with `actor/2`; `World.Reaction` builds them
  from guids and fills in the owner projection.
  """

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.FeignDeath
  alias ThistleTea.Game.Core.Duel.Dueling
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pvp

  @unit_flag_non_attackable 0x00000002
  @unit_flag_non_attackable_2 0x00010000
  @unit_flag_not_selectable 0x02000000
  @unit_flag_taxi_flight 0x00100000
  @unit_flag_immune_to_player 0x00000100
  @unit_flag_immune_to_npc 0x00000200

  def actor(%{object: %{guid: guid}} = entity, projection) when is_map(projection) do
    projection
    |> Map.merge(%{guid: guid, feigning_death?: FeignDeath.successful?(entity), owner_guid: owner_guid(entity)})
    |> Map.merge(unit_projection(entity))
    |> Map.merge(character_projection(entity))
  end

  def owner_player(actor) do
    controller = controller_guid(actor)
    if player_guid?(controller) and controller != guid(actor), do: controller
  end

  def hostile?(source, target) do
    source |> reaction_rank(target) |> rank_reaction() |> Kernel.==(:hostile)
  end

  def friendly?(source, target) do
    source |> reaction_rank(target) |> rank_reaction() |> Kernel.==(:friendly)
  end

  def reaction_rank(source, target) do
    ensure_actors!(source, target)

    cond do
      same_controller?(source, target) ->
        :friendly

      duel_opponents?(source, target) ->
        :hostile

      grouped_players?(source, target) ->
        :friendly

      arena_opponents?(source, target) ->
        :hostile

      true ->
        case reputation_reaction(source, target) do
          {:ok, rank} -> rank
          :none -> template_reaction_rank(source, target)
        end
    end
  end

  def neutral_to_all?(source) do
    ensure_actor!(source)

    source
    |> faction_template()
    |> FactionTemplate.neutral_to_all?()
  end

  def can_initiate_attack?(source) do
    ensure_actor!(source)

    alive?(source) and targetable?(source) and proximity_aggro?(source) and not neutral_to_all?(source)
  end

  def valid_hostile_target?(source, target) do
    alive?(target) and targetable_by?(source, target) and hostile?(source, target) and
      pvp_attack_allowed?(source, target)
  end

  def valid_attack_target?(source, target, opts \\ [])

  def valid_attack_target?(source, target, opts) do
    (alive?(target) or Keyword.get(opts, :allow_dead?, false)) and targetable_by?(source, target, false, opts) and
      attack_reaction_allows?(source, target) and
      pvp_attack_allowed?(source, target)
  end

  def can_attack_without_flagging?(source, target) do
    ensure_actors!(source, target)

    not both_player_controlled?(source, target) or player_pvp?(source) or
      duel_opponents?(source, target) or arena_opponents?(source, target)
  end

  def attackable?(source, target) do
    valid_attack_target?(source, target)
  end

  def can_assist?(source, target) do
    targetable_by?(source, target, true) and
      (not both_player_controlled?(source, target) or same_controller?(source, target) or
         player_projection(target, :duel_started?) != true)
  end

  def targetable_by?(source, target, helpful? \\ false, opts \\ [])

  def targetable_by?(source, target, true, _opts) do
    ensure_actors!(source, target)

    (unit_flags(target) &&& @unit_flag_non_attackable_2) == 0 and assist_flags_allow?(source, target)
  end

  def targetable_by?(source, target, false, opts) do
    ensure_actors!(source, target)

    targetable?(target) and attack_flags_allow?(source, target) and
      (not FeignDeath.successful?(target) or player_controlled?(source) or Keyword.get(opts, :area?, false))
  end

  defp faction_template(%{faction_template: %FactionTemplate{} = faction_template}), do: faction_template
  defp faction_template(_source), do: nil

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

  defp pvp_attack_allowed?(source, target) do
    not both_player_controlled?(source, target) or duel_opponents?(source, target) or
      player_pvp?(target) or arena_opponents?(source, target)
  end

  defp both_player_controlled?(source, target), do: player_controlled?(source) and player_controlled?(target)

  defp grouped_players?(source, target) do
    group = player_projection(source, :group_id)
    not is_nil(group) and group == player_projection(target, :group_id)
  end

  defp arena_opponents?(source, target) do
    player_projection(source, :free_for_all?) == true and player_projection(target, :free_for_all?) == true
  end

  defp player_pvp?(actor), do: player_projection(actor, :pvp?) == true

  defp player_projection(actor, key) do
    case player_owner_guid(actor) do
      owner when is_integer(owner) -> if owner == guid(actor), do: Map.get(actor, key), else: owner_value(actor, key)
      _no_player -> nil
    end
  end

  defp owner_value(%{owner: owner}, key) when is_map(owner), do: Map.get(owner, key)
  defp owner_value(_actor, _key), do: nil

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
    player_guid?(controller_guid(entity))
  end

  defp duel_opponents?(source, target) do
    opponent = player_projection(source, :duel_opponent_guid)

    is_integer(opponent) and opponent > 0 and player_projection(source, :duel_started?) == true and
      opponent == controller_guid(target)
  end

  defp owner_guid(%{owner_guid: owner_guid}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(%{internal: %{possession: %{caster_guid: owner_guid}}}), do: owner_guid
  defp owner_guid(%{internal: %{pet: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(%{internal: %{totem: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(%{game_object: %{created_by: owner_guid}}) when is_integer(owner_guid), do: owner_guid
  defp owner_guid(_entity), do: nil

  defp player_guid?(guid) when is_integer(guid), do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false

  defp guid(%{guid: guid}) when is_integer(guid), do: guid
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

  defp contested_pvp?(actor), do: player_projection(actor, :contested_pvp?) == true

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

  defp reputation_projection(%{owner_guid: owner} = actor) when is_integer(owner) and owner > 0,
    do: map_or_empty(owner_value(actor, :reputation))

  defp reputation_projection(%{reputation: reputation}) when is_map(reputation), do: reputation
  defp reputation_projection(actor), do: map_or_empty(player_projection(actor, :reputation))

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}

  defp player_owner_guid(entity) do
    controller = controller_guid(entity)
    if player_guid?(controller), do: controller
  end

  defp same_controller?(source, target) do
    source_owner = controller_guid(source)
    target_owner = controller_guid(target)
    is_integer(source_owner) and source_owner > 0 and source_owner == target_owner
  end

  defp controller_guid(entity) do
    case owner_guid(entity) do
      owner when is_integer(owner) and owner > 0 -> owner
      _ -> guid(entity)
    end
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
  defp alive?(_target), do: true

  defp targetable?(%{unit_flags: flags}) when is_integer(flags), do: targetable_unit_flags?(flags)
  defp targetable?(_target), do: true

  defp attack_flags_allow?(source, target) do
    not immune_to?(source, target) and not immune_to?(target, source)
  end

  defp assist_flags_allow?(source, target) do
    not is_integer(player_owner_guid(source)) or (unit_flags(target) &&& @unit_flag_immune_to_player) == 0
  end

  defp immune_to?(entity, other) do
    flag = if is_integer(player_owner_guid(other)), do: @unit_flag_immune_to_player, else: @unit_flag_immune_to_npc
    (unit_flags(entity) &&& flag) != 0
  end

  defp unit_flags(%{unit_flags: flags}) when is_integer(flags), do: flags
  defp unit_flags(_entity), do: 0

  defp targetable_unit_flags?(flags) when is_integer(flags) do
    (flags &&&
       (@unit_flag_non_attackable ||| @unit_flag_non_attackable_2 ||| @unit_flag_not_selectable |||
          @unit_flag_taxi_flight)) ==
      0
  end

  defp proximity_aggro?(%{proximity_aggro?: false}), do: false
  defp proximity_aggro?(_source), do: true

  defp unit_projection(%{unit: %Unit{flags: flags}} = entity),
    do: %{unit_flags: if(is_integer(flags), do: flags, else: 0), alive?: not Entity.dead?(entity)}

  defp unit_projection(_entity), do: %{unit_flags: 0, alive?: true}

  defp character_projection(%Character{internal: %{possession: nil}} = character) do
    %{
      pvp?: Pvp.active?(character),
      free_for_all?: Pvp.free_for_all?(character),
      duel_started?: Dueling.active?(character),
      duel_opponent_guid: Dueling.opponent_guid(character)
    }
  end

  defp character_projection(_entity), do: %{}

  defp ensure_actors!(source, target) do
    ensure_actor!(source)
    ensure_actor!(target)
  end

  defp ensure_actor!(%{__struct__: module}) do
    raise ArgumentError,
          "Hostility expects reaction actors, got %#{inspect(module)}{}; build one with actor/2 or World.Reaction"
  end

  defp ensure_actor!(%{guid: _guid}), do: :ok

  defp ensure_actor!(actor) when is_map(actor) do
    raise ArgumentError,
          "Hostility actors need a :guid, got keys #{inspect(Map.keys(actor))}; build one with actor/2, Perception.actor/2, or World.Reaction"
  end

  defp ensure_actor!(actor), do: raise(ArgumentError, "Hostility expects a reaction actor map, got #{inspect(actor)}")
end
