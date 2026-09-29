defmodule ThistleTea.Game.Core.AI.BT.Detection do
  @moduledoc """
  Resolves concealment from immutable behavior-tree observations so target
  acquisition, melee swings, and auto-repeat shots use the same detection rules.
  """

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Math

  def detectable?(entity, guid, %Context{perception: perception, now: now}) do
    detector = entity |> StealthDetection.target_metadata() |> Map.put(:guid, entity.object.guid)
    target = Perception.metadata(perception, guid)
    distance = Perception.distance(perception, guid)
    behind? = behind?(entity, Perception.position(perception, guid))

    StealthDetection.detectable?(detector, target, distance, now, behind?) and
      (not Map.get(target, :stealthed?, false) or StealthDetection.marked_by?(target, entity.object.guid) or
         Perception.line_of_sight?(perception, guid))
  end

  defp behind?(%{movement_block: %{position: {x, y, _z, orientation}}}, {_world, tx, ty, _tz}) do
    Math.behind?({x, y, orientation}, {tx, ty})
  end

  defp behind?(_entity, _position), do: false
end
