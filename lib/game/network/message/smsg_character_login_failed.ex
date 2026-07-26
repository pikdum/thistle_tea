defmodule ThistleTea.Game.Network.Message.SmsgCharacterLoginFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHARACTER_LOGIN_FAILED

  @results %{
    in_progress: 0x3C,
    success: 0x3D,
    no_world: 0x3E,
    duplicate_character: 0x3F,
    no_instances: 0x40,
    failed: 0x41,
    disabled: 0x42,
    no_character: 0x43,
    locked_for_transfer: 0x44
  }

  defstruct [:result]

  def result(key), do: Map.fetch!(@results, key)

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}) do
    <<result::little-size(8)>>
  end
end
