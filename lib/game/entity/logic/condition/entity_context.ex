defmodule ThistleTea.Game.Entity.Logic.Condition.EntityContext do
  @moduledoc """
  Pure projection of an entity and its behavior-tree environment into a
  condition context.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context, as: AIContext
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  @content_patch 10

  def build(entity, %AIContext{} = ai_context, target_guid \\ nil) do
    source = entity |> subject(ai_context.now) |> put_condition_area(ai_context.condition_area)
    target = target_subject(source, ai_context.perception, target_guid)

    Context.new(
      source: source,
      target: target,
      world: %{map_id: map_id(entity)},
      now: ai_context.condition_now,
      content_patch: @content_patch,
      environment: %{condition_results: ai_context.script_conditions}
    )
  end

  defp subject(
         %Character{object: object, unit: unit, player: player, internal: internal, movement_block: movement} =
           character,
         now
       ) do
    common_subject(object, unit, internal, movement, now)
    |> then(fn subject ->
      %{
        subject
        | kind: :player,
          player_owned?: true,
          race: unit.race,
          class: unit.class,
          skills: player.skills,
          spellbook: internal.spellbook,
          quest_log: player.quest_log,
          rewarded_quests: player.rewarded_quests,
          reputation_ranks: player.reputation.ranks,
          group?: nil,
          has_pet?: Character.controlled_guid(character) != nil,
          pet_guid: Character.controlled_guid(character)
      }
    end)
  end

  defp subject(
         %Mob{
           object: object,
           unit: unit,
           internal: %Internal{creature: %Creature{db_guid: db_guid}} = internal,
           movement_block: movement
         },
         now
       ) do
    subject = common_subject(object, unit, internal, movement, now)
    %{subject | kind: :creature, db_guid: db_guid, spellbook: internal.spellbook}
  end

  defp subject(
         %GameObject{object: object, game_object: game_object, internal: internal, movement_block: movement},
         _now
       ) do
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
      go_state: game_object.state
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
      aura_effects: aura_effects(holders)
    }
  end

  defp target_subject(source, _perception, nil), do: source
  defp target_subject(%Subject{guid: guid} = source, _perception, guid), do: source

  defp target_subject(_source, %Perception{} = perception, guid) when is_integer(guid) and guid > 0 do
    metadata = Perception.metadata(perception, guid) || %{}

    %Subject{
      guid: guid,
      kind: Guid.entity_type(guid),
      entry: Guid.entry(guid),
      position: Perception.position(perception, guid),
      level: Map.get(metadata, :level),
      race: Map.get(metadata, :race),
      class: Map.get(metadata, :class),
      gender: Map.get(metadata, :gender),
      alive?: Map.get(metadata, :alive?),
      moving?: Perception.moving?(perception, guid),
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

  defp target_subject(_source, %Perception{}, _guid), do: nil

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
