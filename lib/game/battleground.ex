defmodule ThistleTea.Game.Battleground do
  @moduledoc """
  Shared battleground identity, bracket, and faction rules.
  """

  @warsong_gulch_map 489
  @warsong_gulch_type 2
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def warsong_gulch_map, do: @warsong_gulch_map
  def warsong_gulch_type, do: @warsong_gulch_type

  def team_for_race(race) when race in @alliance_races, do: :alliance
  def team_for_race(race) when race in @horde_races, do: :horde
  def team_for_race(_race), do: nil

  def bracket(level) when level in 10..19, do: 0
  def bracket(level) when level in 20..29, do: 1
  def bracket(level) when level in 30..39, do: 2
  def bracket(level) when level in 40..49, do: 3
  def bracket(level) when level in 50..59, do: 4
  def bracket(60), do: 5
  def bracket(_level), do: nil
end
