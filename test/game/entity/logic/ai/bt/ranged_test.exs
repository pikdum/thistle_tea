defmodule ThistleTea.Game.Entity.Logic.AI.BT.RangedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
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
    test "pacify cancels ranged attacks without firing or consuming ammunition" do
      spell = %Spell{id: 75, prevention_type: 2}

      for type <- [:mod_pacify, :mod_pacify_silence] do
        holder = %Holder{spell: %Spell{id: 24_740}, auras: [%Aura{type: type}]}

        character = %Character{
          object: %Object{guid: 1},
          unit: %Unit{health: 100, auras: [holder]},
          player: %Player{},
          internal: %Internal{auto_shot: %{target_guid: 7, next_at: 0, spell: spell, targets: Target.unit(7)}}
        }

        {_status, result} = BT.tick(Ranged.sequence(), character, Context.new(1_000))
        assert result.internal.auto_shot == nil
        assert [%Effects.CancelAutoRepeat{}] = result.internal.events
      end
    end

    test "stops shooting concealed targets and respects detection and caster-specific marks" do
      spell = %Spell{id: 75, min_range_yards: 8.0, range_yards: 35.0}

      perception_aura = %Holder{
        spell: %Spell{id: 20_600},
        auras: [%Aura{type: :mod_stealth_detect, amount: 50, misc_value: 0}]
      }

      character = %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{health: 100, level: 50, combat_reach: 1.5, ranged_attack_time: 2_000, auras: []},
        internal: %Internal{
          world: WorldRef.open(0),
          auto_shot: %{target_guid: 7, next_at: 0, spell: spell, targets: Target.unit(7)}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      hidden = %{level: 50, player?: true, stealthed?: true, stealth_skill: 250}

      for {metadata, auras, orientation, visible?} <- [
            {hidden, [], 0.0, false},
            {hidden, [perception_aura], 0.0, true},
            {hidden, [perception_aura], :math.pi(), false},
            {Map.put(hidden, :stalked_by, [1]), [], :math.pi(), true},
            {Map.put(hidden, :stalked_by, [2]), [], 0.0, false},
            {Map.put(hidden, :undetectable_until, 1_001), [perception_aura], 0.0, false}
          ] do
        observation = %Observation{
          guid: 7,
          position: {WorldRef.open(0), 20.0, 0.0, 0.0},
          distance: 20.0,
          line_of_sight?: true,
          metadata: metadata
        }

        perception = Perception.new(1_000, nil, %{7 => observation}, %{mobs: [], players: []})
        context = Context.new(1_000, perception: perception)

        caster = %{
          character
          | unit: %{character.unit | auras: auras},
            movement_block: %{character.movement_block | position: {0.0, 0.0, 0.0, orientation}}
        }

        {_status, result} = BT.tick(Ranged.sequence(), caster, context)

        assert Enum.any?(result.internal.events, &is_struct(&1, Effects.LaunchRanged)) == visible?
        refute Enum.any?(result.internal.events, &is_struct(&1, Effects.DeliverSpell))
        assert is_nil(result.internal.auto_shot) == not visible?
        assert Enum.any?(result.internal.events, &is_struct(&1, Effects.CancelAutoRepeat)) == not visible?
      end
    end

    test "measures the dead zone from the edges of both combat reaches" do
      target_guid = 7
      spell = %Spell{id: 75, min_range_yards: 8.0, range_yards: 35.0}

      character = %Character{
        player: %Player{},
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
