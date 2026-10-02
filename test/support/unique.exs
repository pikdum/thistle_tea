defmodule ThistleTea.Test.Unique do
  @moduledoc """
  The suite's single source of unique integers for guids, ids, and names.

  Async tests share the entity registry, `Metadata`, `SpatialHash`, and the
  runtime stores, so two tests holding the same guid misroute each other's
  messages. `System.unique_integer/1` is only unique within one modifier set,
  and its monotonic counter ends a full run in the low thousands, where
  fixture literals and the `CharacterStore` and `ItemStore` counters live.
  Values here come from one counter starting at `0x500000`: above every
  VMangos spawn guid and the summon range, below `Guid.runtime/2`'s range,
  and within a 24-bit low guid.
  """

  @base 0x500000

  def integer, do: @base + System.unique_integer([:positive, :monotonic])
end
