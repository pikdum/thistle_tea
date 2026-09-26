defmodule ThistleTea.Game.Entity.Logic.CastingCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.CastingCombat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "launch/3" do
    test "resets each equipped hand to its current weapon period", context do
      cast = Cast.new(%Spell{interrupt_flags: 8}, Target.none(), 1_000)

      for entity <- [context.player, context.mob], now <- [2_000, -100_000] do
        launched = CastingCombat.launch(entity, cast, now)
        assert launched.internal.blackboard.combat.next_attack_at == now + 1_800
        assert launched.internal.blackboard.combat.next_offhand_attack_at == now + 2_600
        assert launched.internal.blackboard.combat.auto_attacking
        assert launched.internal.ranged_attack_at == entity.internal.ranged_attack_at
      end
    end

    test "preserves timers for triggered, exempt and nonresetting abilities", context do
      reset = %Spell{interrupt_flags: 8}

      casts = [
        %{Cast.new(reset, Target.none(), 1_000) | triggered?: true},
        Cast.new(%{reset | attributes: MapSet.new([:do_not_reset_combat_timers])}, Target.none(), 1_000),
        Cast.new(%Spell{interrupt_flags: 7}, Target.none(), 1_000)
      ]

      for entity <- [context.player, context.mob], cast <- casts do
        assert CastingCombat.launch(entity, cast, 2_000) == entity
      end
    end

    test "does not reset an unequipped or unusable offhand", %{player: player} do
      cast = Cast.new(%Spell{interrupt_flags: 8}, Target.none(), 1_000)

      for entity <- [
            %{player | unit: %{player.unit | offhand_weapon: nil}},
            %{player | player: %{player.player | broken_equipment: [:offhand]}},
            %{player | unit: %{player.unit | class: 11, shapeshift_form: 1}}
          ] do
        launched = CastingCombat.launch(entity, cast, 2_000)
        assert launched.internal.blackboard.combat.next_attack_at == 3_800
        assert launched.internal.blackboard.combat.next_offhand_attack_at == 1_600
      end
    end
  end

  describe "finish/2" do
    test "stops player melee, queued swings and autorepeat without leaving combat", %{player: player} do
      finished = CastingCombat.finish(player, stop_spell())
      refute finished.internal.blackboard.combat.auto_attacking
      assert finished.internal.blackboard.combat.auto_attack_target == nil
      assert finished.internal.blackboard.combat.next_attack_at == 1_500
      assert finished.internal.next_swing_spell == nil
      assert finished.internal.auto_shot == nil
      assert finished.unit.target == 0
      assert finished.internal.in_combat
      assert finished.internal.threat_refs == player.internal.threat_refs
      assert Enum.any?(finished.internal.events, &is_struct(&1, Effects.CancelAutoRepeat))
      assert Enum.any?(finished.internal.events, &match?(%Effects.AttackStop{target_guid: 42}, &1))
      assert CastingCombat.finish(finished, stop_spell()) == finished
    end

    test "uses the creature engagement transition while retaining threat", %{mob: mob} do
      finished = CastingCombat.finish(mob, stop_spell())
      assert finished.unit.target == 0
      assert finished.internal.in_combat
      assert finished.internal.threat == mob.internal.threat
      assert finished.internal.next_swing_spell == nil
      refute finished.internal.blackboard.combat.auto_attacking
      assert Enum.any?(finished.internal.events, &match?(%Effects.AttackerLost{target_guid: 42}, &1))
      assert CastingCombat.finish(finished, stop_spell()) == finished
    end

    test "damage-breakable auras alone do not stop the caster's attacks", context do
      spell = %Spell{aura_interrupt_flags: 2}
      for entity <- [context.player, context.mob], do: assert(CastingCombat.finish(entity, spell) == entity)
    end
  end

  describe "finish/3" do
    test "attack attributes command pets but leave ordinary casters unchanged", context do
      pet = %{context.mob | internal: %{context.mob.internal | pet: %Internal.Pet{kind: :hunter}}}

      for attribute <- [:initiates_combat, :initiate_combat_post_cast] do
        spell = %Spell{id: 17_253, attributes: MapSet.new([attribute])}
        finished = CastingCombat.finish(pet, spell, 77)
        assert [%Effects.PetSpellAttack{target_guid: 77}] = finished.internal.events
        assert CastingCombat.finish(pet, spell, nil) == pet
        assert CastingCombat.finish(pet, spell, 0) == pet
        assert CastingCombat.finish(context.mob, spell, 77) == context.mob
        assert CastingCombat.finish(context.player, spell, 77) == context.player
      end
    end

    test "attack cancellation takes precedence over initiation", %{mob: mob} do
      pet = %{mob | internal: %{mob.internal | pet: %Internal.Pet{kind: :hunter}}}
      spell = %{stop_spell() | attributes: MapSet.new([:cancels_auto_attack_combat, :initiates_combat])}
      finished = CastingCombat.finish(pet, spell, 77)
      assert finished.unit.target == 0
      refute Enum.any?(finished.internal.events, &is_struct(&1, Effects.PetSpellAttack))
    end

    test "triggered completion commands the explicit target without depending on a hit", %{mob: mob} do
      pet = %{mob | internal: %{mob.internal | pet: %Internal.Pet{kind: :hunter}}}
      spell = %Spell{id: 17_253, attributes: MapSet.new([:initiates_combat])}
      payload = %{victim_guid: 77, outcome: :resist, proc_type: :deal_harmful_spell, proc_origin: :aura_or_item}
      hit = SpellFeedback.receive(pet, payload, spell, 2_000)
      assert hit.internal.events == []
      finished = SpellFeedback.receive(pet, %{payload | outcome: :cast_end}, spell, 2_000)
      assert [%Effects.PetSpellAttack{target_guid: 77}] = finished.internal.events
    end
  end

  describe "spell lifecycle" do
    test "cancelling a stopping spell preserves melee attack intent", %{player: player} do
      spell = %{stop_spell() | cast_time_ms: 1_000, interrupt_flags: 8}
      cancelled = player |> Casting.start(spell, Target.none(), 1_000) |> Casting.cancel(1_500)
      assert cancelled.internal.blackboard == player.internal.blackboard
      assert cancelled.internal.auto_shot != nil
      refute Enum.any?(cancelled.internal.events || [], &is_struct(&1, Effects.AttackStop))
    end

    test "channels reset swings once at launch instead of on completion", %{player: player} do
      spell = %Spell{
        id: 10,
        cast_time_ms: 0,
        duration_ms: 2_000,
        interrupt_flags: 8,
        attributes: MapSet.new([:channeled])
      }

      channeling = Casting.start(player, spell, Target.none(), 1_000)
      assert channeling.internal.casting.phase == :channel_tick
      assert channeling.internal.blackboard.combat.next_attack_at == 2_800
      assert channeling.internal.blackboard.combat.next_offhand_attack_at == 3_600
      assert {:finished, finished} = Casting.advance(channeling, 3_000)
      assert finished.internal.blackboard == channeling.internal.blackboard
    end

    test "preparation and interruption retain timers while successful launch resets them", %{player: player} do
      spell = %Spell{id: 133, cast_time_ms: 1_000, interrupt_flags: 8}
      started = Casting.start(player, spell, Target.none(), 1_000)
      assert started.internal.blackboard == player.internal.blackboard
      cancelled = Casting.cancel(started, 1_500)
      assert cancelled.internal.blackboard == player.internal.blackboard
      assert {:finished, launched} = Casting.advance(started, 2_000)
      assert launched.internal.blackboard.combat.next_attack_at == 3_800
      assert launched.internal.blackboard.combat.next_offhand_attack_at == 4_600
    end

    test "a successfully completed spell stops attacks even when it hits no units", %{player: player} do
      finished = player |> Casting.start(stop_spell(), Target.none(), 1_000) |> Casting.complete(1_000)
      assert finished.internal.casting == nil
      refute finished.internal.blackboard.combat.auto_attacking
      assert finished.internal.auto_shot == nil
      assert finished.unit.target == 0
      assert Enum.any?(finished.internal.events, &match?(%Effects.AttackStop{target_guid: 42}, &1))
    end

    test "triggered completion stops attacks but hit feedback does not", %{player: player} do
      spell = stop_spell()
      payload = %{victim_guid: 77, outcome: :normal, proc_type: :deal_harmful_spell, proc_origin: :aura_or_item}
      hit = SpellFeedback.receive(player, payload, spell, 2_000)
      assert hit.internal.blackboard.combat.auto_attacking
      finished = SpellFeedback.receive(player, %{payload | outcome: :cast_end}, spell, 2_000)
      refute finished.internal.blackboard.combat.auto_attacking
      assert finished.internal.auto_shot == nil
      assert finished.internal.blackboard.combat.next_attack_at == 1_500
    end
  end

  defp stop_spell, do: %Spell{id: 1776, cast_time_ms: 0, attributes: MapSet.new([:cancels_auto_attack_combat])}

  defp entities(_context) do
    blackboard =
      Blackboard.new()
      |> Blackboard.enable_auto_attack(%TargetRef{guid: 42})
      |> Blackboard.put_next_at(:next_attack_at, 500, 1_000)
      |> Blackboard.put_next_at(:next_offhand_attack_at, 600, 1_000)

    unit = %Unit{
      health: 100,
      max_health: 100,
      level: 60,
      target: 42,
      auras: [],
      base_attack_time: 1_800,
      offhand_attack_time: 2_600,
      offhand_weapon: %{class: 2, subclass: 15}
    }

    internal = %Internal{
      world: WorldRef.open(0),
      in_combat: true,
      blackboard: blackboard,
      threat: %{42 => 50.0},
      threat_refs: MapSet.new([{42, 7}]),
      ranged_attack_at: 1_700,
      auto_shot: %{spell: %Spell{id: 75}, targets: Target.unit(42), target_guid: 42, next_at: 1_800},
      next_swing_spell: %Spell{id: 78}
    }

    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}

    player = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      unit: unit,
      internal: internal,
      movement_block: movement
    }

    mob = %Mob{object: %Object{guid: 2}, unit: unit, internal: %{internal | auto_shot: nil}, movement_block: movement}
    %{player: player, mob: mob}
  end
end
