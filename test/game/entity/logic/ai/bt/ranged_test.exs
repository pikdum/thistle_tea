defmodule ThistleTea.Game.Entity.Logic.AI.BT.RangedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  describe "active?/2" do
    test "tracks and stops an active auto shot" do
      character = %Character{internal: %Internal{auto_shot: %{target_guid: 7}}}

      assert Ranged.active?(character, Blackboard.new())
      character = Ranged.stop(character)
      refute Ranged.active?(character, Blackboard.new())
      assert [%Effects.CancelAutoRepeat{}] = character.internal.events
    end

    test "does not remain active after death" do
      character = %Character{unit: %Unit{health: 0}, internal: %Internal{auto_shot: %{target_guid: 7}}}

      refute Ranged.active?(character, Blackboard.new())
    end
  end

  describe "sequence/0" do
    test "measures the dead zone from the edges of both combat reaches" do
      target_guid = 7
      spell = %Spell{id: 75, min_range_yards: 8.0, range_yards: 35.0}

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, level: 50, combat_reach: 1.5, ranged_attack_time: 2_000},
        internal: %Internal{
          world: WorldRef.open(0),
          auto_shot: %{target_guid: target_guid, next_at: 0, spell: spell, targets: Target.unit(target_guid)}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      observation = %Observation{
        guid: target_guid,
        position: {WorldRef.open(0), 10.0, 0.0, 0.0},
        distance: 10.0,
        metadata: %{combat_reach: 1.5}
      }

      perception = Perception.new(1_000, nil, %{target_guid => observation}, %{mobs: [], players: []})
      context = Context.new(1_000, perception: perception)

      assert {{:running, 0}, result} = BT.tick(Ranged.sequence(), character, context)
      refute Enum.any?(result.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert result.internal.auto_shot.next_at == 0
    end
  end
end
