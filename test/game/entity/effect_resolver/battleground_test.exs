defmodule ThistleTea.Game.Entity.EffectResolver.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Mob
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

    test "captures an objective incarnation and attributes a pet kill to its admitted owner" do
      world = WorldRef.instance(30, 1)
      pet = Guid.from_low_guid(:pet, 1, 1)
      victim = objective(world)
      binding = %{event1: 46, event2: 2}

      opts = [
        bindings: fn 30, :creature, 100 -> [binding] end,
        metadata: fn ^pet -> %{owner_guid: 1} end,
        participants: fn ^world -> %{1 => %{team: :alliance}} end
      ]

      effect = %Effects.CreatureDefeated{source_guid: pet}

      assert [%Effects.BattlegroundCreatureDeath{world: ^world, defeat: defeat}] =
               Battleground.resolve(victim, effect, opts)

      assert defeat.victim_guid == victim.object.guid
      assert defeat.entry == 11_678
      assert defeat.db_guid == 100
      assert defeat.incarnation_id == 9
      assert defeat.killer_guid == 1
      assert defeat.bindings == [binding]

      assert Battleground.resolve(victim, effect, Keyword.put(opts, :participants, fn _world -> %{} end)) == []
      assert Battleground.resolve(victim, effect, Keyword.put(opts, :bindings, fn _, _, _ -> [] end)) == []
      assert Battleground.resolve(victim, %{effect | source_guid: nil}, opts) == []

      assert Battleground.resolve(
               victim,
               %{effect | source_guid: victim.object.guid},
               Keyword.put(opts, :metadata, fn _guid -> %{} end)
             ) == []
    end

    test "ordinary world kills and summons bypass battleground lookups" do
      effect = %Effects.CreatureDefeated{source_guid: 1}
      opts = [bindings: fn _, _, _ -> flunk("unexpected catalog lookup") end]
      assert Battleground.resolve(objective(WorldRef.open(30)), effect, opts) == []
      victim = objective(WorldRef.instance(30, 1))
      victim = %{victim | internal: %{victim.internal | creature: %Internal.Creature{}}}
      assert Battleground.resolve(victim, effect, opts) == []
    end

    test "a creature death is emitted once and retains its killer after corpse damage" do
      victim = objective(WorldRef.instance(30, 1))
      victim = victim |> Core.take_damage(10, 100, source: 1) |> Core.take_damage(10, 101, source: 2)

      assert [%Effects.CreatureDefeated{source_guid: 1}] =
               Enum.filter(victim.internal.events, &is_struct(&1, Effects.CreatureDefeated))

      assert victim.internal.killed_by == 1
    end
  end

  defp objective(world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 11_678, 100), entry: 11_678},
      unit: %Unit{health: 10, max_health: 10},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: world,
        creature: %Internal.Creature{db_guid: 100},
        spawn: %Internal.Spawn{incarnation_id: 9}
      }
    }
  end
end
