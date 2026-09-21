defmodule ThistleTea.Game.Network.Message.CmsgGroupChangeSubGroup do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_CHANGE_SUB_GROUP

  alias ThistleTea.Game.Player.Groups

  defstruct [:name, :subgroup]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, <<subgroup::little-size(8)>>} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name, subgroup: subgroup}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name, subgroup: subgroup}, state), do: Groups.change_subgroup(state, name, subgroup)
end
