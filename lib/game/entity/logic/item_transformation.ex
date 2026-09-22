defmodule ThistleTea.Game.Entity.Logic.ItemTransformation do
  @moduledoc """
  Preserves permanent and temporary enchants and proportional durability when
  an item-use spell creates a replacement item instance.
  """

  alias ThistleTea.Game.Entity.Data.Item

  def prepare(%Item{} = replacement, %Item{} = original, now) do
    replacement
    |> Item.copy_enchantments(original, now)
    |> copy_durability(original)
  end

  defp copy_durability(%Item{item: %{max_durability: maximum}} = replacement, %Item{
         item: %{durability: current, max_durability: original_maximum}
       })
       when is_integer(maximum) and maximum > 0 and is_integer(current) and is_integer(original_maximum) and
              original_maximum > current and original_maximum > 0 do
    loss = max(div(maximum * (original_maximum - current), original_maximum), 1)
    %{replacement | item: %{replacement.item | durability: max(maximum - loss, 0)}}
  end

  defp copy_durability(replacement, _original), do: replacement
end
