defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Formation do
  @moduledoc false

  @enforce_keys [:membership]
  defstruct [:membership, :leader_position, :leader_orientation, :path, :started_at, :arrives_at, leader_ready?: false]
end
