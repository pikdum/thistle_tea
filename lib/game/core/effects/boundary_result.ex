defmodule ThistleTea.Game.Core.Effects.BoundaryResult do
  @moduledoc """
  Pure owner transitions for values produced by boundary interpreters.
  """

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Commands
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Movement.Charge
  alias ThistleTea.Game.Core.Pet.Totems

  def apply(%{unit: %Unit{}, internal: %Internal{}} = entity, %Commands.ChargePathResolved{} = command) do
    Charge.start(entity, command)
  end

  def apply(%Character{player: %Player{} = player} = character, %Commands.FarsightStarted{guid: guid}) do
    %{character | player: %{player | farsight: guid}}
    |> Entity.mark_broadcast_update()
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
    |> Entity.mark_broadcast_update()
  end

  def apply(%Character{} = character, %Commands.TotemStarted{slot: slot, guid: guid}) do
    Totems.started(character, slot, guid)
  end

  def apply(%Character{} = character, %Commands.TotemStopped{guid: guid}) do
    Totems.stopped(character, guid)
  end
end
