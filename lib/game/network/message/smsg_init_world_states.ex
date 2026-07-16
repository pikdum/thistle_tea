defmodule ThistleTea.Game.Network.Message.SmsgInitWorldStates do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INIT_WORLD_STATES

  defstruct [:map, :area, states: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map, area: area, states: states}) do
    states_binary =
      for {state, value} <- states, into: <<>> do
        <<state::little-size(32), value::little-size(32)>>
      end

    <<map::little-size(32), area::little-size(32), length(states)::little-size(16)>> <> states_binary
  end
end
