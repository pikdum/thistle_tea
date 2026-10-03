defmodule ThistleTea.Game.Core.LocalDefenseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.LocalDefense

  @guard 0x400
  @pvp_enabling 0x00400000

  describe "defender?/1" do
    test "is a town guard or a creature that flags its killer for PvP, never a pet" do
      assert LocalDefense.defender?(mob(extra_flags: @guard))
      assert LocalDefense.defender?(mob(static_flags: @pvp_enabling))
      refute LocalDefense.defender?(mob([]))
      refute LocalDefense.defender?(%{mob(extra_flags: @guard) | internal: %Internal{pet: %{}, creature: %Creature{}}})
    end
  end

  describe "alert/3" do
    test "alerts an area at most once every ten seconds" do
      assert {:alert, cooldowns} = LocalDefense.alert(%{}, 12, 1_000)
      assert {:quiet, ^cooldowns} = LocalDefense.alert(cooldowns, 12, 11_000)
      assert {:alert, other} = LocalDefense.alert(cooldowns, 40, 11_000)
      assert {:alert, %{12 => 11_001}} = LocalDefense.alert(other, 12, 11_001)
    end
  end

  describe "defending?/2" do
    test "warns the other faction only" do
      assert LocalDefense.defending?(:horde, :alliance)
      refute LocalDefense.defending?(:horde, :horde)
      refute LocalDefense.defending?(:horde, nil)
    end
  end

  defp mob(flags) do
    %Mob{internal: %Internal{creature: struct(Creature, Keyword.merge([extra_flags: 0, static_flags: 0], flags))}}
  end
end
