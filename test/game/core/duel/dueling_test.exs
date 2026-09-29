defmodule ThistleTea.Game.Core.Duel.DuelingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Duel.Dueling
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Spell

  describe "requested/2 and started/2" do
    test "projects the arbiter, opponent, and team without entering combat" do
      character = character()

      character =
        Dueling.requested(character, %{
          initiator_guid: 1,
          opponent_guid: 2,
          arbiter_guid: 3
        })

      assert character.player.duel_arbiter == 3
      assert character.player.duel_team == 0
      assert character.internal.duel.state == :requested

      character = Dueling.started(character, %{opponent_guid: 2, team: 1, started_at: 4_000})

      assert character.player.duel_team == 1
      assert character.internal.duel.state == :started
      assert character.internal.duel.started_at == 4_000
      refute character.internal.in_combat
      assert Bitwise.band(character.unit.flags, 0x00080000) == 0
    end

    test "preserves existing combat when the countdown ends" do
      character = character()
      refs = MapSet.new([{20, 1}])

      character = %{
        character
        | unit: %{character.unit | flags: 0x00080000},
          internal: %{character.internal | in_combat: true, last_hostile_time: 3_900, threat_refs: refs}
      }

      character =
        character
        |> Dueling.requested(%{initiator_guid: 1, opponent_guid: 2, arbiter_guid: 3})
        |> Dueling.started(%{opponent_guid: 2, team: 1, started_at: 4_000})

      assert character.internal.in_combat
      assert character.internal.last_hostile_time == 3_900
      assert character.internal.threat_refs == refs
      assert Bitwise.band(character.unit.flags, 0x00080000) != 0
    end
  end

  describe "finish/2" do
    test "removes duel debuffs and clears duel-only combat state" do
      old_debuff = holder(10, 2, 3_000, true)
      duel_debuff = holder(11, 2, 4_000, true)
      pet_debuff = holder(12, 20, 5_000, true)
      own_buff = holder(13, 1, 5_000, false)

      character =
        character()
        |> Dueling.requested(%{initiator_guid: 1, opponent_guid: 2, arbiter_guid: 3})
        |> Dueling.started(%{opponent_guid: 2, team: 1, started_at: 4_000})

      character = %{
        character
        | unit: %{character.unit | target: 2, auras: [old_debuff, duel_debuff, pet_debuff, own_buff]},
          player: %{character.player | combo_points: 4},
          internal: %{
            character.internal
            | combo_target_guid: 2,
              blackboard: %Blackboard{
                navigation: %Blackboard.Navigation{target: 2},
                combat: %Blackboard.Combat{
                  auto_attacking: true,
                  attack_started: true,
                  auto_attack_target: %TargetRef{guid: 2}
                }
              }
          }
      }

      {character, events} =
        Dueling.finish(character, %{opponent_guid: 2, opponent_pet_guid: 20, started_at: 4_000, now: 6_000})

      assert Enum.map(character.unit.auras, & &1.spell.id) == [10, 13]
      assert character.unit.target == 0
      assert character.player.combo_points == 0
      assert character.player.duel_arbiter == 0
      assert character.player.duel_team == 0
      assert character.internal.duel == nil
      refute character.internal.in_combat
      refute character.internal.blackboard.combat.auto_attacking
      assert Enum.any?(events, &match?(%Effects.AttackStop{source_guid: 1, target_guid: 2}, &1))
    end

    test "finishing notifies the attacked opponent after selection changes" do
      character = active_character()
      memory = Blackboard.enable_auto_attack(Blackboard.new(), %TargetRef{guid: 2})

      character = %{
        character
        | unit: %{character.unit | target: 77},
          internal: %{character.internal | blackboard: memory}
      }

      {finished, events} = Dueling.finish(character, %{opponent_guid: 2, started_at: 4_000, now: 6_000})
      assert finished.unit.target == 0
      assert Enum.count(events, &match?(%Effects.AttackStop{target_guid: 2}, &1)) == 1
      refute Enum.any?(events, &match?(%Effects.AttackStop{target_guid: 77}, &1))
    end
  end

  describe "duel lethal damage" do
    test "opponent damage stops at one health and queues defeat" do
      character = active_character()

      {character, absorbed} =
        Entity.take_damage_with_absorb(character, 150, 5_000, source: 2, source_owner: 2)

      assert character.unit.health == 1
      assert absorbed == 51
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelDefeat{source_guid: 2}, &1))
    end

    test "an opponent pet receives duel credit through its owner" do
      character = active_character()

      {character, _absorbed} =
        Entity.take_damage_with_absorb(character, 100, 5_000, source: 20, source_owner: 2)

      assert character.unit.health == 1
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelDefeat{source_guid: 2}, &1))
    end

    test "third-party lethal damage kills normally and interrupts the duel" do
      character = active_character()

      {character, _absorbed} =
        Entity.take_damage_with_absorb(character, 100, 5_000, source: 9, source_owner: 9)

      assert character.unit.health == 0
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelInterrupted{}, &1))
    end

    test "a spell reflected by the opponent can defeat its original caster" do
      character = active_character()

      {character, _absorbed} =
        Entity.take_damage_with_absorb(character, 100, 5_000,
          source: 1,
          source_owner: 1,
          reflected_by: 2
        )

      assert character.unit.health == 1
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelDefeat{source_guid: 2}, &1))
    end
  end

  defp active_character do
    character()
    |> Dueling.requested(%{initiator_guid: 1, opponent_guid: 2, arbiter_guid: 3})
    |> Dueling.started(%{opponent_guid: 2, team: 1, started_at: 4_000})
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 20, flags: 0, target: 0, auras: []},
      player: %Player{combo_points: 0},
      internal: %Internal{events: [], blackboard: %Blackboard{}, threat_refs: MapSet.new()}
    }
  end

  defp holder(id, caster_guid, applied_at, negative?) do
    %Holder{
      spell: %Spell{id: id, effects: []},
      caster_guid: caster_guid,
      applied_at: applied_at,
      negative?: negative?,
      auras: []
    }
  end
end
