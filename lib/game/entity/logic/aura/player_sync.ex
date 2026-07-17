defmodule ThistleTea.Game.Entity.Logic.Aura.PlayerSync do
  @moduledoc false
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player

  def sync(%Character{unit: %{auras: holders}, player: %Player{}} = character) when is_list(holders) do
    tracked_type =
      Enum.find_value(holders, fn %Holder{auras: auras} ->
        Enum.find_value(auras, fn
          %Aura{type: :track_creatures, misc_value: creature_type}
          when is_integer(creature_type) and creature_type > 0 ->
            creature_type

          _aura ->
            nil
        end)
      end)

    track_creatures = if tracked_type, do: 1 <<< (tracked_type - 1), else: 0
    %{character | player: %{character.player | track_creatures: track_creatures}}
  end

  def sync(entity), do: entity
end
