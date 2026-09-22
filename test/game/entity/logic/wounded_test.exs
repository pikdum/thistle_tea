defmodule ThistleTea.Game.Entity.Logic.WoundedTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  setup [:creature]

  describe "MovementStats.recompute/1" do
    test "uses exact health boundaries and only reduces running", %{mob: mob} do
      for {health, multiplier, bits} <- [
            {1_000, 1.0, 0},
            {160, 1.0, 0},
            {159, 0.7, 0x100},
            {110, 0.7, 0x100},
            {109, 0.6, 0x300},
            {60, 0.6, 0x300},
            {59, 0.5, 0x700},
            {1, 0.5, 0x700},
            {0, 1.0, 0}
          ] do
        updated = %{mob | unit: %{mob.unit | health: health}} |> Reactive.sync_health() |> MovementStats.recompute()
        assert_in_delta updated.movement_block.run_speed, 8.0 * multiplier, 0.000001
        assert updated.movement_block.base_run_speed == 8.0
        assert updated.movement_block.walk_speed == mob.movement_block.walk_speed
        assert updated.movement_block.swim_speed == mob.movement_block.swim_speed
        assert updated.movement_block.run_back_speed == mob.movement_block.run_back_speed
        assert (updated.unit.aura_state &&& 0x700) == bits
        assert MovementStats.recompute(updated) == updated
      end
    end

    test "layers wounds with snares and restores the canonical speed", %{mob: mob} do
      snare = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: :mod_decrease_speed, amount: -50}]}
      wounded = %{mob | unit: %{mob.unit | health: 50, auras: [snare]}} |> MovementStats.recompute()
      assert wounded.movement_block.run_speed == 2.0
      healed = Core.heal(wounded, 1_000)
      assert healed.movement_block.run_speed == 4.0
      restored = %{healed | unit: %{healed.unit | auras: []}} |> MovementStats.recompute()
      assert restored.movement_block.run_speed == 8.0
    end

    test "exempts pets and world bosses but still slows charmed creatures", %{mob: mob} do
      wounded = %{mob | unit: %{mob.unit | health: 50}}

      for kind <- [:hunter, :summon, :guardian, :mini_pet, :creature_pet] do
        pet = %{wounded | internal: %{wounded.internal | pet: %Pet{kind: kind, owner_guid: 1}}}
        assert MovementStats.recompute(pet).movement_block.run_speed == 8.0
      end

      for kind <- [:charmed, :possessed] do
        controlled = %{wounded | internal: %{wounded.internal | pet: %Pet{kind: kind, owner_guid: 1}}}
        assert MovementStats.recompute(controlled).movement_block.run_speed == 4.0
      end

      for {rank, flags, speed} <- [{0, 0, 4.0}, {1, 0, 4.0}, {3, 0, 8.0}, {1, 0x40, 8.0}] do
        configured = %{wounded | internal: %{wounded.internal | creature: %Creature{rank: rank, static_flags2: flags}}}
        assert MovementStats.recompute(configured).movement_block.run_speed == speed
      end

      player = %Character{unit: wounded.unit, movement_block: wounded.movement_block}
      assert MovementStats.recompute(player).movement_block.run_speed == 8.0
    end
  end

  describe "Core.take_damage/4" do
    test "damage and healing project each speed transition once", %{mob: mob} do
      wounded = Core.take_damage(mob, 850, 1_000)
      assert wounded.unit.health == 150
      assert_in_delta wounded.movement_block.run_speed, 5.6, 0.000001
      assert [%Effects.MovementSpeedChanged{movement_type: :run_speed}] = speeds(wounded)

      unchanged = %{wounded | internal: %{wounded.internal | events: []}} |> Core.take_damage(1, 1_001)
      assert speeds(unchanged) == []
      healed = Core.heal(unchanged, 100)
      assert healed.movement_block.run_speed == 8.0
      assert (healed.unit.aura_state &&& 0x700) == 0
      assert [%Effects.MovementSpeedChanged{speed: 8.0}] = speeds(healed)
    end

    test "regeneration, death and respawn clear wounded state", %{mob: mob} do
      wounded = Core.take_damage(mob, 950, 1_000)
      assert wounded.movement_block.run_speed == 4.0
      regenerated = Regen.tick(wounded, 2_000)
      assert regenerated.unit.health > 160
      assert regenerated.movement_block.run_speed == 8.0
      dead = Core.kill(wounded, 3_000)
      assert dead.unit.health == 0
      assert dead.movement_block.run_speed == 8.0
      assert (dead.unit.aura_state &&& 0x700) == 0
      respawned = Mob.respawn(dead)
      assert respawned.unit.health == 1_000
      assert respawned.movement_block.run_speed == 8.0
      assert (respawned.unit.aura_state &&& 0x700) == 0
    end
  end

  describe "MobBT.reset_after_combat/2" do
    test "restores health and speed before returning home", %{mob: mob} do
      wounded = Core.take_damage(mob, 950, 1_000)
      restored = MobBT.reset_after_combat(wounded, Context.new(2_000))
      assert restored.unit.health == 1_000
      assert restored.movement_block.run_speed == 8.0
      assert (restored.unit.aura_state &&& 0x700) == 0
      assert restored.internal.blackboard.navigation.returning_home?
    end
  end

  defp speeds(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.MovementSpeedChanged))

  defp creature(_context) do
    unit = %Unit{health: 1_000, max_health: 1_000, level: 10, flags: 0, aura_state: 0, auras: []}

    movement =
      struct!(
        MovementBlock,
        Map.merge(MovementBlock.player_speeds(), %{run_speed: 8.0, base_run_speed: 8.0, position: {0.0, 0.0, 0.0, 0.0}})
      )

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: unit,
      movement_block: movement,
      internal: %Internal{
        creature: %Creature{regenerate_stats: 1},
        spawn: %Spawn{unit: unit, movement_block: movement, position: {0.0, 0.0, 0.0}}
      }
    }

    %{mob: mob}
  end
end
