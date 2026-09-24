defmodule ThistleTea.Game.Entity.Server.ScriptSpells do
  @moduledoc """
  Prepares a mob's spellbook for scripts received from another owner, including
  spells used by the waypoint routes and nested scripts they start.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  def prepare(%Mob{} = mob, steps, waypoints \\ WaypointLoader.context(), load_spell \\ &SpellLoader.cached/1) do
    {ids, _visited} = spell_ids(mob, steps, waypoints, MapSet.new())
    existing = mob.internal.spellbook || %{}

    spellbook =
      ids
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(existing, &1))
      |> Enum.reduce(existing, fn id, spellbook ->
        case load_spell.(id) do
          %Spell{} = spell -> Map.put(spellbook, id, spell)
          nil -> spellbook
        end
      end)

    %{mob | internal: %{mob.internal | spellbook: spellbook}}
  end

  defp spell_ids(mob, steps, waypoints, visited) do
    Enum.reduce(steps, {[], visited}, fn %ScriptStep{} = step, {ids, visited} ->
      {route_steps, visited} = route_steps(mob, step, waypoints, visited)
      nested = step.sub_scripts |> Map.values() |> List.flatten()
      {nested_ids, visited} = spell_ids(mob, nested ++ route_steps, waypoints, visited)
      {List.wrap(ScriptStep.cast_spell_id(step)) ++ nested_ids ++ ids, visited}
    end)
  end

  defp route_steps(mob, %ScriptStep{command: :start_waypoints} = step, waypoints, visited) do
    key = {step.datalong, step.dataint, step.dataint2}

    if MapSet.member?(visited, key) do
      {[], visited}
    else
      steps =
        case Waypoints.resolve(waypoints, mob, step) do
          %WaypointRoute{points: points} -> Enum.flat_map(points, fn {_id, point} -> point.script_steps end)
          nil -> []
        end

      {steps, MapSet.put(visited, key)}
    end
  end

  defp route_steps(_mob, _step, _waypoints, visited), do: {[], visited}
end
