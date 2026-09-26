defmodule ThistleTea.Game.Entity.EventSink.GroupScripts do
  @moduledoc """
  Starts one selected script on its source and current creature group or party.
  Each recipient runs the same resolved steps in its own owner and world copy.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.World.System.Party

  def emit(entity, %Effects.StartGroupScript{steps: steps, target_guid: target}, context) do
    source = entity.object.guid
    world = entity.internal.world
    target = target || 0
    Context.cast(context, {:start_script, steps, target, world})

    entity
    |> members()
    |> Enum.uniq()
    |> Enum.reject(&(&1 == source))
    |> Enum.each(&Entity.start_script(&1, steps, target, world))

    entity
  end

  defp members(%Mob{} = mob), do: CreatureGroups.members(mob.internal.world, mob.object.guid)

  defp members(%Character{} = character) do
    case Party.group_of(character.object.guid) do
      %Group{members: members} -> Enum.map(members, & &1.guid)
      _ungrouped -> []
    end
  end
end
