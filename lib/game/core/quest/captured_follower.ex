defmodule ThistleTea.Game.Core.Quest.CapturedFollower do
  @moduledoc "Aura-backed captured animals follow one player, expire when lost, and leave after delivery or logout."

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Change
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Aura.Transition
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  @captures %{21_827 => 10_981, 21_863 => 10_990}

  def spell?(%Spell{id: id}), do: is_map_key(@captures, id)
  def spell?(_spell), do: false
  def interval(%Spell{} = spell, %Effect{aura: :dummy}), do: if(spell?(spell), do: 2_000)
  def interval(%Spell{}, %Effect{}), do: nil

  def reconcile(%Character{unit: %{auras: holders}} = character, now, contexts) when is_list(holders) do
    retained = Enum.reject(holders, &lost?(character, &1, now, contexts))

    if retained == holders,
      do: {character, []},
      else: Transition.run(character, %Change{holders: retained, cause: :source_unavailable, now: now})
  end

  def reconcile(entity, _now, _contexts), do: {entity, []}

  def after_remove(%Character{object: %{guid: player}}, %Holder{} = holder, cause) do
    if captured?(holder) do
      delay = if cause == :source_unavailable, do: 1_000, else: 2_000

      [
        %Effects.ForwardScriptSteps{
          target_guid: holder.caster_guid,
          source_guid: player,
          world: capture_world(holder),
          steps: [%ScriptStep{command: :despawn, datalong: delay}]
        }
      ]
    else
      []
    end
  end

  def after_remove(_entity, _holder, _cause), do: []

  def tick_events(%Character{object: %{guid: player}}, %Holder{} = holder) do
    if captured?(holder),
      do: [%Effects.EnsureCapturedFollower{creature_guid: holder.caster_guid, player_guid: player}],
      else: []
  end

  def tick_events(_entity, _holder), do: []

  def release(%Character{} = character, now), do: Aura.remove_spells(character, Map.keys(@captures), now)

  defp capture_world(%Holder{cast_context: %{caster_position: {world, _x, _y, _z}}}), do: world
  defp capture_world(%Holder{}), do: nil

  defp lost?(character, %Holder{} = holder, now, contexts) do
    due? = Enum.any?(holder.auras, &(is_integer(&1.next_tick_at) and &1.next_tick_at <= now))
    context = Map.get(contexts, {holder.spell.id, holder.caster_guid, holder.item_source}, holder.cast_context)
    captured?(holder) and due? and not available?(character, context)
  end

  defp available?(
         %Character{movement_block: %{position: {x, y, z, _orientation}}, internal: %{world: world}} = character,
         %{caster_available?: true, caster_position: {world, cx, cy, cz}}
       ) do
    Death.alive?(character) and Math.distance({x, y, z}, {cx, cy, cz}) <= 50.0
  end

  defp available?(_character, _context), do: false

  defp captured?(%Holder{spell: %Spell{id: id}, caster_guid: guid}) do
    is_map_key(@captures, id) and is_integer(guid) and Guid.entity_type(guid) == :mob and
      Guid.entry(guid) == @captures[id]
  end
end
