defmodule ThistleTea.Game.Network.Message.CmsgUnlearnSkill do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_UNLEARN_SKILL

  alias ThistleTea.Game.Player.Professions

  defstruct [:skill_id]

  @impl ClientMessage
  def from_binary(<<skill_id::little-size(32)>>), do: %__MODULE__{skill_id: skill_id}

  @impl ClientMessage
  def handle(%__MODULE__{skill_id: skill_id}, %{ready: true, character: %Character{}} = state) do
    Professions.unlearn(state, skill_id)
  end

  def handle(_message, state), do: state
end
