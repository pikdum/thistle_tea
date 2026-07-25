defmodule ThistleTea.Game.Entity.Logic.DuelingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  describe "requested/2 and started/2" do
    test "projects the arbiter, opponent, team, and combat state" do
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
      assert character.internal.in_combat
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
              blackboard: %Blackboard{target: 2, auto_attacking: true, attack_started: true}
          }
      }

      {character, events} =
        Dueling.finish(character, %{opponent_guid: 2, opponent_pet_guid: 20, started_at: 4_000})

      assert Enum.map(character.unit.auras, & &1.spell.id) == [10, 13]
      assert character.unit.target == 0
      assert character.player.combo_points == 0
      assert character.player.duel_arbiter == 0
      assert character.player.duel_team == 0
      assert character.internal.duel == nil
      refute character.internal.in_combat
      refute character.internal.blackboard.auto_attacking
      assert Enum.any?(events, &match?(%Effects.AttackStop{source_guid: 1, target_guid: 2}, &1))
    end
  end

  describe "duel lethal damage" do
    test "opponent damage stops at one health and queues defeat" do
      character = active_character()

      {character, absorbed} =
        Core.take_damage_with_absorb(character, 150, 5_000, source: 2, source_owner: 2)

      assert character.unit.health == 1
      assert absorbed == 51
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelDefeat{source_guid: 2}, &1))
    end

    test "an opponent pet receives duel credit through its owner" do
      character = active_character()

      {character, _absorbed} =
        Core.take_damage_with_absorb(character, 100, 5_000, source: 20, source_owner: 2)

      assert character.unit.health == 1
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelDefeat{source_guid: 2}, &1))
    end

    test "third-party lethal damage kills normally and interrupts the duel" do
      character = active_character()

      {character, _absorbed} =
        Core.take_damage_with_absorb(character, 100, 5_000, source: 9, source_owner: 9)

      assert character.unit.health == 0
      assert Enum.any?(character.internal.events, &match?(%Effects.DuelInterrupted{}, &1))
    end

    test "a spell reflected by the opponent can defeat its original caster" do
      character = active_character()

      {character, _absorbed} =
        Core.take_damage_with_absorb(character, 100, 5_000,
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
