defmodule ThistleTea.Game.Entity.Logic.Aura.ObjectSync do
  @moduledoc false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Appearance

  def sync(%{object: %Object{}, unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    scale_multiplier =
      Enum.reduce(holders, 1.0, fn %Holder{auras: auras}, multiplier ->
        Enum.reduce(auras, multiplier, fn
          %Aura{type: :mod_scale, amount: amount}, acc when is_number(amount) -> acc * max(1.0 + amount / 100, 0.0)
          _aura, acc -> acc
        end)
      end)

    Appearance.project(entity, scale_multiplier)
  end

  def sync(entity), do: entity
end
