defmodule ThistleTea.Game.Network.Message.MsgRaidTargetUpdateResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_RAID_TARGET_UPDATE

  defstruct [:icon, :target, :icons]

  @impl ServerMessage
  def to_binary(%__MODULE__{icons: icons}) when is_list(icons) do
    <<1>> <> Enum.map_join(icons, fn {icon, target} -> <<icon::little-size(8), target::little-size(64)>> end)
  end

  def to_binary(%__MODULE__{icon: icon, target: target}) do
    <<0, icon::little-size(8), target::little-size(64)>>
  end
end
