defmodule ThistleTea.Game.Network.Message.CmsgUseItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_USE_ITEM

  alias ThistleTea.Game.Network.Message

  defstruct [:bag, :slot, :spell_count, :targets]

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot, spell_count, targets::binary>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot,
      spell_count: spell_count,
      targets: targets
    }
  end
end
