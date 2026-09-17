defmodule ThistleTea.Game.Network.Message.SmsgSpelldispellog do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLDISPELLOG

  defstruct [:victim, :caster, spells: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{victim: victim, caster: caster, spells: spells}) do
    BinaryUtils.pack_guid(victim) <>
      BinaryUtils.pack_guid(caster) <>
      <<length(spells)::little-size(32)>> <>
      Enum.reduce(spells, <<>>, fn id, acc -> acc <> <<id::little-size(32)>> end)
  end
end
