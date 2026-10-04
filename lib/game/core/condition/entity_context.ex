defmodule ThistleTea.Game.Core.Condition.EntityContext do
  @moduledoc """
  Pure projection of an entity and its behavior-tree environment into a
  condition context. `static/1` projects only the facts a creature spawn can
  never change, for specializing its conditions when it is built. A perceived
  player target carries the quest, skill, reputation, and item facts its own
  process publishes as `condition_subject`, so creatures can gate on them the
  way vmangos reads the player directly. A player's own scripts read the
  inventory, exploration, and reputation facts it published the same way,
  since its struct alone cannot count the items it carries.
  """

  alias ThistleTea.Game.Core.AI.BT.Context, as: AIContext
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Honor.Rank
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Pet.MiniPet
  alias ThistleTea.Game.Core.Spell

  @content_patch 10
  @unit_flags 46
  @npc_flags 147
  @game_object_flags 9

  def build(entity, %AIContext{} = ai_context, target_guid \\ nil) do
    source =
      entity
      |> subject(ai_context.now)
      |> put_condition_area(ai_context.condition_area)
      |> put_own_facts(ai_context.perception)

    target = target_subject(source, ai_context.perception, target_guid)

    Context.new(
      source: source,
      target: target,
      world: %{
        map_id: map_id(entity),
        instance_data: ai_context.instance_data,
        saved_variables: ai_context.saved_variables,
        active_game_events: ai_context.active_game_events
      },
      now: ai_context.condition_now,
      content_patch: @content_patch,
      environment: %{condition_results: condition_results(ai_context, target_guid)}
    )
  end

  def static(%Mob{object: object, internal: %Internal{creature: %Creature{db_guid: db_guid}}}) do
    Context.new(
      source: %Subject{guid: object.guid, kind: :creature, db_guid: db_guid},
      content_patch: @content_patch
    )
  end

  defp condition_results(%AIContext{script_conditions_by_target: results}, target_guid)
       when is_map(results) and map_size(results) > 0 do
    Map.get(results, target_guid, %{})
  end

  defp condition_results(%AIContext{script_conditions: results}, _target_guid), do: results

  def subject(%Character{object: object, unit: unit, player: player, internal: internal} = character, now) do
    common_subject(object, unit, internal, character.movement_block, now)
    |> then(fn subject ->
      %{
        subject
        | kind: :player,
          player_owned?: true,
          race: unit.race,
          class: unit.class,
          honor_rank: Rank.visual_from_number(player.honor_rank || 0),
          skills: player.skills,
          skill_bonuses: player.skill_bonuses,
          spell_ids: Subject.spell_ids(internal.spellbook),
          quest_log: player.quest_log,
          rewarded_quests: player.rewarded_quests,
          reputation_ranks: player.reputation.ranks,
          group?: nil,
          has_pet?: Character.controlled_guid(character) != nil,
          pet_guid: Character.controlled_guid(character),
          mini_pet_entry: MiniPet.entry(character)
      }
    end)
  end

  def subject(
        %Mob{
          object: object,
          unit: unit,
          internal: %Internal{creature: %Creature{db_guid: db_guid}} = internal,
          movement_block: movement
        },
        now
      ) do
    subject = common_subject(object, unit, internal, movement, now)
    %{subject | kind: :creature, db_guid: db_guid, spell_ids: Subject.spell_ids(internal.spellbook)}
  end

  def subject(%GameObject{object: object, game_object: game_object, internal: internal, movement_block: movement}, _now) do
    %Subject{
      guid: object.guid,
      kind: :game_object,
      entry: object.entry,
      position: movement.position,
      map_id: internal.world.map_id,
      area_id: internal.area,
      db_guid: game_object_db_guid(object.guid, internal),
      owner_guid: game_object.created_by,
      player_owned?: nil,
      go_spawned?: true,
      go_state: game_object.state,
      flags: %{@game_object_flags => game_object.flags || 0}
    }
  end

  defp common_subject(object, unit, internal, movement, now) do
    holders = unit.auras || []

    %Subject{
      guid: object.guid,
      entry: object.entry,
      position: movement.position,
      map_id: internal.world.map_id,
      area_id: internal.area,
      level: unit.level,
      gender: unit.gender,
      alive?: unit.health > 0,
      moving?: Movement.moving?(%{internal: internal, movement_block: movement}, now),
      combat?: internal.in_combat == true,
      health: unit.health,
      max_health: unit.max_health,
      mana: unit.power1,
      max_mana: unit.max_power1,
      aura_ids: MapSet.new(Aura.spell_stacks(%{unit: unit}), &elem(&1, 0)),
      aura_effects: aura_effects(holders),
      flags: %{@unit_flags => unit.flags || 0, @npc_flags => unit.npc_flags || 0}
    }
  end

  defp target_subject(source, _perception, nil), do: source
  defp target_subject(%Subject{guid: guid} = source, _perception, guid), do: source

  defp target_subject(_source, %Perception{} = perception, guid) when is_integer(guid) and guid > 0 do
    metadata = Perception.metadata(perception, guid) || %{}

    guid
    |> metadata_subject(metadata,
      entry: Perception.entry(perception, guid),
      position: Perception.position(perception, guid),
      moving?: Perception.moving?(perception, guid)
    )
    |> put_player_facts(Map.get(metadata, :condition_subject))
  end

  defp target_subject(_source, %Perception{}, _guid), do: nil

  defp put_player_facts(%Subject{kind: :player, guid: guid} = subject, %Subject{kind: :player, guid: guid} = published) do
    %{
      subject
      | team: published.team,
        skills: published.skills,
        skill_bonuses: published.skill_bonuses,
        spell_ids: published.spell_ids,
        quest_log: published.quest_log,
        rewarded_quests: published.rewarded_quests,
        reputation: published.reputation,
        reputation_ranks: published.reputation_ranks,
        explored_areas: published.explored_areas,
        item_counts: published.item_counts,
        item_counts_with_bank: published.item_counts_with_bank,
        equipped_item_ids: published.equipped_item_ids,
        argent_dawn_commission?: published.argent_dawn_commission?,
        mini_pet_entry: published.mini_pet_entry
    }
  end

  defp put_player_facts(subject, _published), do: subject

  defp put_own_facts(%Subject{kind: :player, guid: guid} = subject, %Perception{} = perception) do
    case Perception.metadata(perception, guid) do
      %{condition_subject: %Subject{kind: :player, guid: ^guid} = published} ->
        %{
          subject
          | team: published.team,
            reputation: published.reputation,
            explored_areas: published.explored_areas,
            item_counts: published.item_counts,
            item_counts_with_bank: published.item_counts_with_bank,
            equipped_item_ids: published.equipped_item_ids,
            argent_dawn_commission?: published.argent_dawn_commission?
        }

      _unpublished ->
        subject
    end
  end

  defp put_own_facts(subject, _perception), do: subject

  def metadata_subject(guid, metadata, opts \\ []) do
    %Subject{
      guid: guid,
      kind: Guid.entity_type(guid),
      entry: Keyword.get(opts, :entry, Map.get(metadata, :entry, Guid.entry(guid))),
      position: Keyword.get(opts, :position),
      level: Map.get(metadata, :level),
      race: Map.get(metadata, :race),
      class: Map.get(metadata, :class),
      honor_rank: Rank.visual_from_number(Map.get(metadata, :honor_rank)),
      gender: Map.get(metadata, :gender),
      alive?: Map.get(metadata, :alive?),
      moving?: Keyword.get(opts, :moving?),
      combat?: Map.get(metadata, :in_combat),
      health: Map.get(metadata, :health_pct),
      max_health: if(is_number(Map.get(metadata, :health_pct)), do: 100),
      mana: Map.get(metadata, :mana_pct),
      max_mana: if(is_number(Map.get(metadata, :mana_pct)), do: 100),
      aura_ids: metadata |> Map.get(:aura_stacks, %{}) |> Map.keys() |> MapSet.new(),
      player_owned?: Map.get(metadata, :owner_player_guid) != nil,
      owner_guid: Map.get(metadata, :owner_guid),
      has_pet?: Map.get(metadata, :controlled_guid) != nil,
      pet_guid: Map.get(metadata, :controlled_guid),
      db_guid: Map.get(metadata, :db_guid),
      go_spawned?: Map.get(metadata, :go_spawned?),
      loot_state: Map.get(metadata, :loot_state),
      go_state: Map.get(metadata, :go_state)
    }
  end

  defp aura_effects(holders) do
    MapSet.new(
      for %Holder{spell: %Spell{id: id}, auras: auras} <- holders,
          %{index: index} <- auras,
          do: {id, index}
    )
  end

  defp map_id(%{internal: %Internal{world: world}}), do: world.map_id

  defp put_condition_area(%Subject{} = subject, {zone_id, area_id}) when is_integer(zone_id) and is_integer(area_id) do
    %{subject | zone_id: zone_id, area_id: area_id}
  end

  defp put_condition_area(%Subject{} = subject, _condition_area), do: subject

  defp game_object_db_guid(guid, %Internal{summon: nil}), do: Guid.low_guid(guid)
  defp game_object_db_guid(_guid, %Internal{}), do: nil
end
