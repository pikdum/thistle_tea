defmodule ThistleTea.Game.Entity.Logic.ShamanTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Shaman

  defp shaman do
    %Mob{object: %Object{guid: 1}, unit: %Unit{level: 40}, internal: %Internal{}}
  end

  describe "trigger_weapon_enchant/5" do
    test "uses enchant chance for windfury and PPM for frostbrand" do
      payload = %{outcome: :normal, victim_guid: 2}
      windfury = %{effect: %{amount: 20, spell_id: 8233}, attack_time_ms: 2500}
      frostbrand = %{effect: %{amount: 0, spell_id: 8034}, attack_time_ms: 3000}

      triggered = Shaman.trigger_weapon_enchant(shaman(), payload, windfury, 0.0, fn -> 0.2 end)
      assert [%{type: :trigger_spell, spell_id: 8233, target_guid: 2}] = triggered.internal.events

      triggered = Shaman.trigger_weapon_enchant(shaman(), payload, frostbrand, 9.0, fn -> 0.4 end)
      assert [%{type: :trigger_spell, spell_id: 8034}] = triggered.internal.events

      unchanged = Shaman.trigger_weapon_enchant(shaman(), payload, frostbrand, 9.0, fn -> 0.5 end)
      assert unchanged.internal.events == []
    end

    test "does not proc from avoided attacks" do
      payload = %{outcome: :miss, victim_guid: 2}
      proc = %{effect: %{amount: 100, spell_id: 8026}, attack_time_ms: 2000}

      assert Shaman.trigger_weapon_enchant(shaman(), payload, proc, 0.0, fn -> 0.0 end).internal.events == []
    end
  end

  describe "flametongue_damage/3" do
    test "matches the VMangos weapon-speed and fire-power coefficient" do
      assert Shaman.flametongue_damage(325, 100, 2_000) == 14
      assert Shaman.flametongue_damage(325, 0, 4_000) == 13
    end
  end
end
