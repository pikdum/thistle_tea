defmodule ThistleTea.Game.World.Entity.Player.Inspection do
  @moduledoc """
  Player inspection admission shared by equipment and honor requests.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Network.Message.SmsgInspect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Reaction

  def inspect(%{character: %Character{} = character} = state, guid) do
    character = %{character | unit: %{character.unit | target: guid}}

    if available?(character, guid), do: Outbound.send_packet(%SmsgInspect{guid: guid})

    %{state | character: character, target: guid}
  end

  def available?(character, guid, opts \\ [])

  def available?(%Character{} = character, guid, opts) when is_integer(guid) and guid > 0 do
    online? = Keyword.get(opts, :online?, &Entity.online?/1)
    position = Keyword.get(opts, :position, &World.position/1)
    attackable? = Keyword.get(opts, :attackable?, &Reaction.valid_attack_target?/2)

    Guid.entity_type(guid) == :player and online?.(guid) and in_range?(character, position.(guid)) and
      not attackable?.(character, guid)
  end

  def available?(_character, _guid, _opts), do: false

  defp in_range?(%Character{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}, {world, px, py, pz}) do
    Math.distance({x, y, z}, {px, py, pz}) <= 10.0
  end

  defp in_range?(_character, _position), do: false
end
