defmodule ThistleTea.Game.World.Entity.EffectResolver.WhenGroupedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.WhenGrouped
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Test.Unique

  describe "resolve/2" do
    test "applies its effects only while both players share a group" do
      [thrower, target, outsider] = for _ <- 1..3, do: Guid.from_low_guid(:player, Unique.integer())
      animation = %Effects.EmoteAnimation{emote_id: 4}
      grouped = %WhenGrouped{guids: [thrower, target], effects: [animation]}

      assert EffectResolver.resolve(nil, grouped) == []

      :ok = PartySystem.invite(thrower, "Thrower", target)
      {:ok, _group} = PartySystem.accept(target, "Target")
      on_exit(fn -> Enum.each([thrower, target], &PartySystem.leave/1) end)

      assert EffectResolver.resolve(nil, grouped) == [animation]
      assert EffectResolver.resolve(nil, %{grouped | guids: [thrower, outsider]}) == []
    end
  end
end
