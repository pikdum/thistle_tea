defmodule ThistleTea.Game.Network.Message.SmsgPartyCommandResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PARTY_COMMAND_RESULT

  defstruct operation: 0, name: "", result: 0

  def op_invite, do: 0
  def op_leave, do: 2

  def code(:ok), do: 0
  def code(:bad_player_name), do: 1
  def code(:target_not_in_group), do: 2
  def code(:group_full), do: 3
  def code(:already_in_group), do: 4
  def code(:not_in_group), do: 5
  def code(:not_leader), do: 6
  def code(:wrong_faction), do: 7

  @impl ServerMessage
  def to_binary(%__MODULE__{operation: operation, name: name, result: result}) do
    <<operation::little-size(32)>> <> name <> <<0, result::little-size(32)>>
  end
end
