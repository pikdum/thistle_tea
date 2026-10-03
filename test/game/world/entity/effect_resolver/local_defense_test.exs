defmodule ThistleTea.Game.World.Entity.EffectResolver.LocalDefenseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.LocalDefense

  @orc 2
  @human 1
  @goldshire 87

  describe "resolve/3" do
    setup [:guard]

    test "alerts the killer's enemies in the guard's area, through pets too", %{guard: guard} do
      world = guard.internal.world
      pet = Guid.from_low_guid(:pet, 1, 1)

      opts = [
        metadata: fn
          ^pet -> %{owner_guid: 7}
          7 -> %{race: @orc}
          8 -> %{race: @human}
        end,
        area_of: fn ^world, {1.0, 2.0, 3.0, _orientation} -> @goldshire end
      ]

      assert [%Effects.LocalDefenseAlert{world: ^world, area_id: @goldshire, attacking_team: :horde}] =
               LocalDefense.resolve(guard, %Effects.CreatureDefeated{source_guid: pet}, opts)

      assert [%Effects.LocalDefenseAlert{attacking_team: :alliance}] =
               LocalDefense.resolve(guard, %Effects.CreatureDefeated{source_guid: 8}, opts)
    end

    test "stays quiet for creature kills, unknown areas, and ordinary creatures", %{guard: guard} do
      creature = Guid.from_low_guid(:unit, 299, 1)
      opts = [metadata: fn _guid -> %{race: @orc} end, area_of: fn _world, _position -> @goldshire end]

      assert LocalDefense.resolve(guard, %Effects.CreatureDefeated{source_guid: creature}, opts) == []

      assert LocalDefense.resolve(guard, %Effects.CreatureDefeated{source_guid: 7}, [
               {:area_of, fn _, _ -> nil end} | opts
             ]) == []

      ordinary = %{guard | internal: %{guard.internal | creature: %Creature{extra_flags: 0}}}
      assert LocalDefense.resolve(ordinary, %Effects.CreatureDefeated{source_guid: 7}, opts) == []
    end
  end

  defp guard(_context) do
    guard = %Mob{
      internal: %Internal{world: WorldRef.open(0), creature: %Creature{extra_flags: 0x400}},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
    }

    %{guard: guard}
  end
end
