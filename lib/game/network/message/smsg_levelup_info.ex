defmodule ThistleTea.Game.Network.Message.SmsgLevelupInfo do
  @moduledoc false

  use ThistleTea.Game.Network.ServerMessage, :SMSG_LEVELUP_INFO

  defstruct new_level: 1,
            health: 0,
            mana: 0,
            rage: 0,
            focus: 0,
            energy: 0,
            happiness: 0,
            strength: 0,
            agility: 0,
            stamina: 0,
            intellect: 0,
            spirit: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<
      message.new_level::little-size(32),
      message.health::little-size(32),
      message.mana::little-size(32),
      message.rage::little-size(32),
      message.focus::little-size(32),
      message.energy::little-size(32),
      message.happiness::little-size(32),
      message.strength::little-size(32),
      message.agility::little-size(32),
      message.stamina::little-size(32),
      message.intellect::little-size(32),
      message.spirit::little-size(32)
    >>
  end
end
