defmodule ThistleTea.Game.Network.Message.SmsgGuildEvent do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_EVENT

  defstruct [:event, descriptions: []]

  @events %{
    promotion: 0,
    demotion: 1,
    motd: 2,
    joined: 3,
    left: 4,
    removed: 5,
    leader_is: 6,
    leader_changed: 7,
    disbanded: 8,
    tabard_changed: 9,
    roster_update: 11,
    signed_on: 12,
    signed_off: 13
  }

  @impl ServerMessage
  def to_binary(%__MODULE__{event: event, descriptions: descriptions}) do
    <<Map.fetch!(@events, event)::8, length(descriptions)::8>> <>
      IO.iodata_to_binary(Enum.map(descriptions, &(&1 <> <<0>>)))
  end
end
