defmodule ThistleTea.Game.Entity.Logic.BoundaryResult do
  @moduledoc """
  Pure owner transitions for values produced by boundary interpreters.
  """

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core

  def apply(
        %Character{movement_block: %MovementBlock{} = movement_block} = character,
        %Commands.ChargePathResolved{} = command
      ) do
    movement_block = %{
      movement_block
      | spline_nodes: command.path,
        duration: command.duration_ms,
        spline_flags: 0x100,
        position: command.destination
    }

    %{character | movement_block: movement_block}
  end

  def apply(%Character{player: %Player{} = player} = character, %Commands.FarsightStarted{guid: guid}) do
    %{character | player: %{player | farsight: guid}}
    |> Core.mark_broadcast_update()
  end

  def apply(
        %Character{internal: %Internal{} = internal, unit: %Unit{} = unit} = character,
        %Commands.ChannelGameObjectStarted{guid: guid}
      ) do
    %{
      character
      | internal: %{internal | channel_game_object_guid: guid, channel_game_object_owned?: true},
        unit: %{unit | channel_object: guid}
    }
    |> Core.mark_broadcast_update()
  end

  def apply(%Character{internal: %Internal{} = internal} = character, %Commands.TotemStarted{slot: slot, guid: guid}) do
    totem_guids = Map.put(internal.totem_guids, slot, guid)
    %{character | internal: %{internal | totem_guids: totem_guids}}
  end
end
