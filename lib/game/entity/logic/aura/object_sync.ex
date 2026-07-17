defmodule ThistleTea.Game.Entity.Logic.Aura.ObjectSync do
  @moduledoc false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit

  def sync(%{object: %Object{} = object, unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    scale_multiplier =
      Enum.reduce(holders, 1.0, fn %Holder{auras: auras}, multiplier ->
        Enum.reduce(auras, multiplier, fn
          %Aura{type: :mod_scale, amount: amount}, acc when is_number(amount) -> acc * max(1.0 + amount / 100, 0.0)
          _aura, acc -> acc
        end)
      end)

    object = %{object | scale_x: (object.base_scale_x || 1.0) * scale_multiplier}
    %{entity | object: object}
  end

  def sync(entity), do: entity
end
