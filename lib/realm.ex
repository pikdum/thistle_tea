defmodule ThistleTea.Realm do
  @moduledoc """
  Realm-list type and the matching world-PvP rules.
  """

  def type, do: Application.get_env(:thistle_tea, :realm_type, 8)
  def pvp_rules, do: if(type() in [1, 8], do: :pvp, else: :normal)
end
