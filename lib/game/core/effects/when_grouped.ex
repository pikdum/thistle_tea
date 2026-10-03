defmodule ThistleTea.Game.Core.Effects.WhenGrouped do
  @moduledoc """
  Effects that apply only while two players share a party or raid. Group
  membership lives with the party system, so the owner boundary decides.
  """

  @enforce_keys [:guids, :effects]
  defstruct [:guids, :effects]
end
