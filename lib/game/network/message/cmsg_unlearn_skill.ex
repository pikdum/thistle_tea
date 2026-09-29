defmodule ThistleTea.Game.Network.Message.CmsgUnlearnSkill do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_UNLEARN_SKILL

  defstruct [:skill_id]

  @impl ClientMessage
  def from_binary(<<skill_id::little-size(32)>>), do: %__MODULE__{skill_id: skill_id}
end
