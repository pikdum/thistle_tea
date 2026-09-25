defmodule ThistleTea.Game.World.SpellEnvironment do
  @moduledoc "Resolves current indoor and outdoor spell context from terrain or a passenger's transport."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Transport
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Transports

  def context(%Character{} = character, %Spell{} = spell) do
    if Environment.restricted?(spell), do: outdoors(character)
  end

  def context(_caster, _spell), do: nil

  def outdoors(%Character{movement_block: %MovementBlock{transport_guid: guid, transport_position: position}})
      when is_integer(guid) do
    case Transports.get(guid) do
      %{route_kind: :ship, display_id: display} -> Transport.outdoors?(display, position)
      %{route_kind: :animation} -> true
      _unknown -> nil
    end
  end

  def outdoors(%Character{internal: %{world: world}, movement_block: %{position: {x, y, z, _}}}) do
    Pathfinding.outdoors(world.map_id, {x, y, z})
  end

  def outdoors(_character), do: nil
end
