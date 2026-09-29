defmodule ThistleTea.Game.Core.Spell.LaunchCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.LaunchCombat

  setup do
    %{
      player: %{guid: 1},
      creature: %{guid: Guid.runtime(:mob, 2)},
      spell: %Spell{speed: 20.0, effects: [%Effect{type: :school_damage}]}
    }
  end

  describe "duration/4" do
    test "player projectiles hold through flight with a half-second margin", ctx do
      assert LaunchCombat.duration(ctx.player, ctx.spell, ctx.creature, 1_200) == 1_700
      assert LaunchCombat.duration(ctx.player, ctx.spell, %{guid: 2}, 1_200) == 5_000
      pet = Map.put(ctx.creature, :owner_guid, 2)
      assert LaunchCombat.duration(ctx.player, ctx.spell, pet, 8_000) == 8_500
      assert LaunchCombat.duration(pet, ctx.spell, ctx.creature, 1_200) == nil
      assert LaunchCombat.duration(pet, ctx.spell, %{guid: Guid.runtime(:mob, 3)}, 1_200) == 1_700
    end

    test "the five-second minimum follows the victim's combat timer rules", ctx do
      for target <- [
            %{guid: Guid.runtime(:pet, 3), owner_guid: 2},
            Map.put(ctx.creature, :charmed_by, 2),
            Map.put(ctx.creature, :no_threat_list?, true)
          ] do
        assert LaunchCombat.duration(ctx.player, ctx.spell, target, 1_200) == 5_000
      end

      totem = Map.put(ctx.creature, :owner_guid, 2)
      assert LaunchCombat.duration(ctx.player, ctx.spell, totem, 1_200) == 1_700
    end

    test "NPC projectiles and helpful, instant or exempt spells do not initiate", ctx do
      refute LaunchCombat.duration(ctx.creature, ctx.spell, ctx.player, 1_200)
      refute LaunchCombat.duration(ctx.player, ctx.spell, ctx.player, 1_200)
      refute LaunchCombat.duration(ctx.player, ctx.spell, ctx.creature, 0)
      refute LaunchCombat.duration(ctx.player, %{ctx.spell | speed: 0}, ctx.creature, 1_200)
      refute LaunchCombat.duration(ctx.player, %{ctx.spell | effects: [%Effect{type: :heal}]}, ctx.creature, 1_200)

      for flag <- [:no_threat, :no_initial_threat, :threat_only_on_miss] do
        refute LaunchCombat.duration(ctx.player, %{ctx.spell | attributes: MapSet.new([flag])}, ctx.creature, 1_200)
      end
    end

    test "active threat holds non-self casts even when initial threat is suppressed", ctx do
      spell = %Spell{attributes: MapSet.new([:active_threat, :no_initial_threat])}
      assert LaunchCombat.duration(ctx.player, spell, ctx.creature, 0) == 5_000
      assert LaunchCombat.duration(ctx.creature, spell, ctx.player, 0) == 5_000
      refute LaunchCombat.duration(ctx.player, spell, ctx.player, 0)
      assert LaunchCombat.duration(Map.put(ctx.player, :in_combat, true), spell, ctx.player, 0) == 5_000
      projectile = %{ctx.spell | attributes: MapSet.new([:active_threat])}
      assert LaunchCombat.duration(ctx.player, projectile, ctx.creature, 8_000) == 8_500
    end
  end
end
