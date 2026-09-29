defmodule ThistleTea.Game.Core.Combat.CombatTimerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Combat.CombatTimer
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid

  setup [:actors]

  describe "hold/4" do
    test "the longest window retains its opponent until contact", ctx do
      held = CombatTimer.hold(ctx.player, -10_000, 8_000, ctx.mob)
      held = CombatTimer.hold(held, -9_000, 1_500, ctx.other)
      assert CombatTimer.remaining(held, -9_000) == 7_000
      assert held.internal.combat_timer_target == ctx.mob

      unrelated = CombatTimer.attack(held, ctx.other, -8_750)
      assert CombatTimer.remaining(unrelated, -8_750) == 6_750
      contacted = CombatTimer.attack(unrelated, ctx.mob, -8_750)
      assert CombatTimer.remaining(contacted, -8_750) == 750
      assert contacted.internal.combat_timer_target == nil
      assert CombatTimer.remaining(contacted, -8_000) == 0
    end

    test "short windows are not extended by PvE contact", ctx do
      held = CombatTimer.hold(ctx.player, 100, 500, ctx.mob)
      contacted = CombatTimer.attack(held, ctx.mob, 200)
      assert CombatTimer.remaining(contacted, 200) == 400
    end

    test "death and explicit cleanup reject stale windows", ctx do
      dead = %{ctx.player | unit: %{ctx.player.unit | health: 0}}
      assert CombatTimer.hold(dead, 0, 5_000, ctx.mob) == dead
      held = CombatTimer.hold(ctx.player, 0, 5_000, ctx.mob)
      cleared = CombatTimer.clear(held)
      assert cleared.internal.combat_timer_target == nil
      assert cleared.internal.last_hostile_time == nil
      assert CombatTimer.remaining(cleared, 100) == 0
    end
  end

  describe "attack/4" do
    test "ordinary creatures request only the next combat check", ctx do
      attacked = CombatTimer.attack(ctx.player, ctx.mob, 1_250)
      assert attacked.internal.in_combat
      assert CombatTimer.remaining(attacked, 1_250) == 750
      assert CombatTimer.remaining(attacked, 2_000) == 0
    end

    test "PvP contact and no-threat-list victims retain five seconds", ctx do
      for opponent <- [2, %{guid: ctx.mob, no_threat_list?: true}, %{guid: ctx.mob, charmed_by: 2}] do
        attacked = CombatTimer.attack(ctx.player, opponent, 1_250)
        assert CombatTimer.remaining(attacked, 1_250) == 5_000
      end

      held = CombatTimer.hold(ctx.player, 0, 8_000, ctx.mob)
      assert CombatTimer.remaining(CombatTimer.attack(held, 2, 1_000), 1_000) == 7_000
    end
  end

  describe "attacked/3" do
    test "incoming creature hits hold players and their pets for five seconds", ctx do
      for entity <- [ctx.player, ctx.pet] do
        attacked = CombatTimer.attacked(entity, ctx.mob, 1_000)
        assert CombatTimer.remaining(attacked, 1_000) == 5_000
        assert attacked.internal.combat_timer_target == ctx.mob
      end
    end
  end

  describe "next_check_at/2" do
    test "held windows wake at expiry and expired combat on the next check", ctx do
      assert CombatTimer.next_check_at(ctx.player, 1_250) == nil

      held = CombatTimer.hold(ctx.player, 1_000, 5_000, ctx.mob)
      assert CombatTimer.next_check_at(held, 1_250) == 6_000
      assert CombatTimer.next_check_at(held, 6_250) == 7_000

      assert CombatTimer.next_check_at(CombatTimer.clear(held), 1_250) == 2_000
    end
  end

  describe "uses_timer?/1" do
    test "classifies actual ownership and creature-template rules", ctx do
      assert CombatTimer.uses_timer?(ctx.player)
      assert CombatTimer.uses_timer?(ctx.pet)
      npc_pet = %{ctx.pet | internal: %{ctx.pet.internal | pet: %Pet{owner_guid: ctx.mob}}}
      refute CombatTimer.uses_timer?(npc_pet)
      charmed = %{npc_pet | unit: %{npc_pet.unit | charmed_by: 2}}
      assert CombatTimer.uses_timer?(charmed)
      template = %{npc_pet | internal: %{npc_pet.internal | creature: %Creature{extra_flags: 0x800}}}
      assert CombatTimer.uses_timer?(template)
      refute CombatTimer.uses_timer?(%{guid: ctx.mob, owner_guid: 1})
    end
  end

  defp actors(_context) do
    %{
      player: %Character{object: %Object{guid: 1}, unit: %Unit{health: 100}, internal: %Internal{}},
      pet: %Mob{
        object: %Object{guid: Guid.runtime(:pet, 1)},
        unit: %Unit{health: 100},
        internal: %Internal{pet: %Pet{owner_guid: 1}}
      },
      mob: Guid.runtime(:mob, 2),
      other: Guid.runtime(:mob, 3)
    }
  end
end
