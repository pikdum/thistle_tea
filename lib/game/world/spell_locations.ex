defmodule ThistleTea.Game.World.SpellLocations do
  @moduledoc "Resolves destinations from cached coordinates and nearby creatures, corpses, and objects."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.Spell.LocationTargets.Selection
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.SpellObjects
  alias ThistleTea.Game.World.SpellTargetInfo
  alias ThistleTea.Game.World.SpellUnits

  def resolve(caster, %Spell{} = spell, %Target{} = targets, focus \\ nil) do
    spell.effects
    |> Enum.filter(&LocationTargets.location?/1)
    |> Enum.reduce_while(%LocationTargets{}, fn effect, snapshot ->
      case selection(caster, spell, effect, targets, focus) do
        %Selection{} = selected ->
          {:cont, %{snapshot | by_effect: Map.put(snapshot.by_effect, effect.index, selected)}}

        :unchanged ->
          {:cont, snapshot}

        {:error, reason} ->
          {:halt, %{snapshot | error: reason}}

        nil ->
          {:halt, %{snapshot | error: :bad_targets}}
      end
    end)
  end

  defp selection(caster, spell, effect, targets, focus) do
    cond do
      LocationTargets.database?(effect) -> database_selection(caster, spell)
      LocationTargets.selected_unit?(effect) -> selected_unit(caster, spell, effect, targets)
      true -> scripted_selection(caster, spell, effect, targets, focus)
    end
  end

  defp selected_unit(caster, spell, effect, targets) do
    guid = Target.unit_guid(targets)

    case selected_position(caster, spell, effect, targets, guid) do
      {:ok, {x, y, z}} ->
        height = if spell.id == 28_863, do: z + 0.3, else: z
        %Selection{guid: guid, position: {x, y, height}, kind: :unit}

      error ->
        error
    end
  end

  defp selected_position(%{object: %{guid: guid}, unit: _unit} = caster, _spell, effect, _targets, guid) do
    if LocationTargets.enemy?(effect) do
      {:error, :bad_targets}
    else
      {x, y, z, _orientation} = caster.movement_block.position
      {:ok, {x, y, z}}
    end
  end

  defp selected_position(caster, spell, effect, targets, guid) when is_integer(guid) do
    world = caster.internal.world
    target_type = if LocationTargets.enemy?(effect), do: :target_enemy, else: :any_unit
    validation_spell = %{spell | effects: [%{effect | implicit_target_a: target_type, implicit_target_b: nil}]}

    with true <- Guid.entity_type(guid) in [:player, :mob, :pet],
         true <- is_pid(Entity.pid(guid)),
         %{position: {^world, x, y, z}} = info <- SpellTargetInfo.build(caster, guid, validation_spell),
         :ok <- CastValidation.validate_target(caster, validation_spell, targets, info) do
      {:ok, {x, y, z}}
    else
      {:error, _reason} = error -> error
      _missing -> {:error, :bad_targets}
    end
  end

  defp selected_position(_caster, _spell, _effect, _targets, _guid), do: {:error, :bad_targets}

  defp database_selection(caster, spell) do
    case SpellLoader.target_position(spell.id) do
      %{map: map, x: x, y: y, z: z} when map == caster.internal.world.map_id ->
        %Selection{position: {x, y, z}, kind: :database}

      _missing_or_other_map ->
        :unchanged
    end
  end

  defp scripted_selection(caster, spell, effect, targets, focus) do
    candidates = [
      unit_candidate(caster, spell, effect, targets),
      object_candidate(caster, spell, effect, focus)
    ]

    candidates
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
    |> case do
      {_unselected, _distance, guid, kind} ->
        case World.position(guid) do
          {world, x, y, z} when world == caster.internal.world ->
            %Selection{guid: guid, kind: kind, position: {x, y, z}}

          _ ->
            nil
        end

      nil ->
        nil
    end
  end

  defp unit_candidate(caster, spell, effect, targets) do
    case SpellUnits.nearest_candidate(caster, spell, effect, targets) do
      {unselected, distance, guid} -> {unselected, distance, guid, :unit}
      nil -> nil
    end
  end

  defp object_candidate(caster, spell, effect, focus) do
    case SpellObjects.nearest_candidate(caster, spell, effect, focus) do
      {guid, distance} -> {true, distance, guid, :game_object}
      nil -> nil
    end
  end
end
