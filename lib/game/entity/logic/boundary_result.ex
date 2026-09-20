defmodule ThistleTea.Game.Entity.Logic.BoundaryResult do
  @moduledoc """
  Pure owner transitions for values produced by boundary interpreters.
  """

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.Totems

  def apply(%Character{} = character, %Commands.ChargePathResolved{} = command) do
    Movement.start_timed_path(character, command.path, command.duration_ms, command.started_at, run?: true)
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

  def apply(%Character{} = character, %Commands.TotemStarted{slot: slot, guid: guid}) do
    Totems.started(character, slot, guid)
  end

  def apply(%Character{} = character, %Commands.TotemStopped{guid: guid}) do
    Totems.stopped(character, guid)
  end
end
