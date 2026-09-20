defmodule ThistleTea.Game.Entity.EffectResolver.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EffectResolver.Battleground
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  describe "resolve/3" do
    test "captures pet ownership and dead teammates near either their body or ghost" do
      world = WorldRef.instance(489, 1)
      other_world = WorldRef.instance(489, 2)
      pet = Guid.from_low_guid(:pet, 1, 1)
      corpse = Corpse.guid_for(3)
      other_corpse = Corpse.guid_for(5)

      victim = %Character{
        object: %Object{guid: 8},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      opts = [
        participants: fn ^world -> Map.new(1..8, &{&1, %{team: :alliance}}) end,
        metadata: fn
          ^pet -> %{owner_guid: 1}
          guid -> %{alive?: guid not in [2, 3, 5]}
        end,
        position: fn
          ^corpse -> {world, 3.0, 0.0, 0.0}
          ^other_corpse -> {other_world, 3.0, 0.0, 0.0}
          3 -> {world, 200.0, 0.0, 0.0}
          4 -> {other_world, 0.0, 0.0, 0.0}
          5 -> {world, 200.0, 0.0, 0.0}
          6 -> nil
          7 -> {world, 75.0, 0.0, 0.0}
          _guid -> {world, 0.0, 0.0, 0.0}
        end
      ]

      effect = %Effects.PlayerDefeated{source_guid: pet, count_death?: false}
      assert [%Effects.BattlegroundDeath{world: ^world, defeat: defeat}] = Battleground.resolve(victim, effect, opts)
      assert defeat.killer_guid == 1
      assert defeat.victim_guid == 8
      refute defeat.count_death?
      assert Enum.sort(defeat.nearby_guids) == [1, 2, 3, 8]
      assert Battleground.resolve(victim, effect, participants: fn _world -> %{} end) == []
    end

    test "lethal damage emits one defeat even when subsequent damage hits the corpse" do
      victim = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 10, max_health: 10},
        player: %Player{},
        internal: %Internal{}
      }

      victim = victim |> Core.take_damage(10, 100, source: 2) |> Core.take_damage(10, 101, source: 3)

      assert [%Effects.PlayerDefeated{source_guid: 2, count_death?: true}] =
               Enum.filter(victim.internal.events, &is_struct(&1, Effects.PlayerDefeated))
    end
  end
end
