defmodule ThistleTea.Game.Inbound.CmsgUseItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_USE_ITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.UsableItems

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

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{}} = state),
    do: UsableItems.use(state, {message.bag, message.slot}, message.targets)

  def handle(%__MODULE__{}, state), do: state
end
