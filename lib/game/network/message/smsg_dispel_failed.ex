defmodule ThistleTea.Game.Network.Message.SmsgDispelFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DISPEL_FAILED

  defstruct [:caster, :target, spells: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{caster: caster, target: target, spells: spells}) do
    <<caster::little-size(64), target::little-size(64)>> <>
      Enum.reduce(spells, <<>>, fn id, acc -> acc <> <<id::little-size(32)>> end)
  end
end
