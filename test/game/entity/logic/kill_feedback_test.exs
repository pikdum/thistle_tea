defmodule ThistleTea.Game.Entity.Logic.KillFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.KillFeedback
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule

  setup [:entities]

  describe "capture/4" do
    test "captures one fatal blow independently of the original tap", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | loot: %Loot{tapped_by: %Tap{player: 77}}}}
      dead = Core.take_damage(mob, 100, 0, source: 88)
      assert [%Effects.KillOutcome{target_guid: 88, victim: victim}] = outcomes(dead)
      assert victim.guid == mob.object.guid
      assert victim.level == 60
      assert victim.reward_target?
      dead = Core.take_damage(dead, 100, 1, source: 99)
      assert [%Effects.KillOutcome{target_guid: 88}] = outcomes(dead)
    end

    test "does not redirect a pet's killing blow to its owner", %{mob: mob} do
      pet = Guid.from_low_guid(:pet, 1, 2)
      dead = Core.take_damage(mob, 100, 0, source: pet, source_owner: 88)
      assert [%Effects.KillOutcome{target_guid: ^pet}] = outcomes(dead)
    end

    test "captures player deaths through the same health transition", %{character: character} do
      dead = Core.take_damage(character, 100, 0, source: 88)
      assert [%Effects.KillOutcome{target_guid: 88, victim: %{reward_target?: true}}] = outcomes(dead)
    end

    test "ignores nonlethal, absorbed, environmental, and self-inflicted damage", %{mob: mob} do
      assert outcomes(Core.take_damage(mob, 99, 0, source: 88)) == []
      assert outcomes(Core.take_damage(mob, 100, 0)) == []
      assert outcomes(Core.take_damage(mob, 100, 0, source: mob.object.guid)) == []
      protected = %{mob | internal: %{mob.internal | godmode: true}}
      assert outcomes(Core.take_damage(protected, 100, 0, source: 88)) == []
      assert KillFeedback.capture(mob, 100, 1, 88) == mob
    end

    test "retains target eligibility for pets, totems, and creatures without rewards", %{mob: mob} do
      pet = %{mob | object: %{mob.object | guid: Guid.from_low_guid(:pet, 1, 2)}}
      totem = %{mob | internal: %{mob.internal | totem: %Totem{}}}
      no_xp = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | static_flags: 2}}}
      zero_xp = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | experience_multiplier: 0.0}}}

      for target <- [pet, totem, no_xp, zero_xp] do
        assert [%Effects.KillOutcome{victim: %{reward_target?: false}}] =
                 target |> Core.take_damage(100, 0, source: 88) |> outcomes()
      end
    end

    test "delivers the captured outcome to the fatal attacker", %{mob: mob} do
      killer = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      Entity.register(killer)
      dead = Core.take_damage(mob, 100, 0, source: killer)
      [outcome] = outcomes(dead)
      EventSink.emit(dead, outcome)
      assert_receive {:"$gen_cast", {:kill_outcome, victim}}
      assert victim == outcome.victim
    end
  end

  describe "receive/3" do
    test "procs for an eligible max-level kill without an XP award", %{character: character, mob: mob} do
      character = with_talent(character)
      [event] = mob |> Core.take_damage(100, 0, source: character.object.guid) |> outcomes()
      result = KillFeedback.receive(character, event.victim, 0)
      assert [%Effects.TriggerSpell{source_guid: 1, spell_id: 15_271}] = triggers(result)
      assert result.player.xp == 0
    end

    test "rejects gray and nonrewarding victims and dead attackers", %{character: character, mob: mob} do
      character = with_talent(character)
      [event] = mob |> Core.take_damage(100, 0, source: 1) |> outcomes()

      for victim <- [%{event.victim | level: 48}, %{event.victim | reward_target?: false}] do
        assert triggers(KillFeedback.receive(character, victim, 0)) == []
      end

      dead = %{character | unit: %{character.unit | health: 0}}
      assert triggers(KillFeedback.receive(dead, event.victim, 0)) == []
    end

    test "NPC kill procs do not require a player reward target", %{mob: mob} do
      mob = with_talent(mob)
      victim = %KillFeedback.Victim{guid: 2, level: 1, reward_target?: false}
      assert [%Effects.TriggerSpell{spell_id: 15_271}] = triggers(KillFeedback.receive(mob, victim, 0))
    end

    test "the player owner queues the proc independently of reward messages", %{character: character, mob: mob} do
      character = with_talent(character)
      [event] = mob |> Core.take_damage(100, 0, source: 1) |> outcomes()
      state = %State{guid: 1, character: character}

      assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:kill_outcome, event.victim}, state)

      assert [%Effects.TriggerSpell{spell_id: 15_271}] = triggers(state.character)
    end
  end

  describe "eligible?/4" do
    test "kill masks ignore hit, school, and family restrictions but retain cast-end separation" do
      rule = %ProcRule{school_mask: 4, spell_family: 3, family_mask_0: 1, proc_ex: 2}
      spell = %{talent() | proc_rule: rule}
      assert Proc.eligible?(spell, nil, :kill, :none)
      refute Proc.eligible?(spell, nil, :kill, :cast_end)
      spell = %{spell | proc_rule: %{rule | proc_ex: 0x80000}}
      refute Proc.eligible?(spell, nil, :kill, :none)
    end
  end

  defp outcomes(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.KillOutcome))
  defp triggers(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.TriggerSpell))

  defp with_talent(entity) do
    {entity, _events} = Aura.apply_spell(entity, entity.object.guid, 60, talent(), 0)
    entity
  end

  defp talent do
    %Spell{
      id: 15_338,
      duration_ms: -1,
      proc_type_mask: 2,
      proc_chance: 100,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 15_271}]
    }
  end

  defp entities(_context) do
    unit = %Unit{health: 100, max_health: 100, level: 60, auras: []}

    character = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{xp: 0, next_level_xp: 0},
      internal: %Internal{}
    }

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: unit,
      internal: %Internal{creature: %Creature{experience_multiplier: 1.0}}
    }

    %{character: character, mob: mob}
  end
end
