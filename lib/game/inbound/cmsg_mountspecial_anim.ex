defmodule ThistleTea.Game.Inbound.CmsgMountspecialAnim do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_MOUNTSPECIAL_ANIM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = character} = state) do
    World.broadcast_packet(%Message.SmsgMountspecialAnim{guid: character.object.guid}, character, include_self?: false)
    state
  end

  def handle(%__MODULE__{}, state), do: state
end
