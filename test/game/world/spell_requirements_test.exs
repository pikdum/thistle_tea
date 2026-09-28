defmodule ThistleTea.Game.World.SpellRequirementsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Corpse, as: CorpseComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.Network.Message.SmsgClearCooldown
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Requirements
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpellRequirements
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "resolve/3" do
    test "implicit pet range uses the active pet even when the packet selects the caster", %{caster: caster} do
      pet = body(:mob, caster.internal.world, {50.0, 0.0, 0.0}, %{alive?: true, faction_template: friendly()})
      caster = Companion.activate(caster, :hunter_pet, %EntityRef{guid: pet, entry: 1, spell_id: 1515})
      spell = %{facing_spell() | effects: [%Effect{type: :heal, implicit_target_a: :pet}]}
      requirements = SpellRequirements.resolve(caster, spell, Target.self(caster.object.guid))
      assert requirements.cast_target.info.guid == pet
      assert Requirements.validate(caster, spell, requirements) == {:error, :out_of_range}
    end
  end

  describe "corpse/2" do
    test "rejects living, friendly, wrong-type, ghost, airborne and invisible targets", %{caster: caster, spell: spell} do
      for {kind, override} <- [
            {:mob, %{alive?: true}},
            {:mob, %{faction_template: friendly()}},
            {:mob, %{creature_type: 1}},
            {:player, %{ghost?: true}},
            {:player, %{unit_flags: 0x00100000}},
            {:mob, %{invisibility: %{0 => 100}}}
          ] do
        guid = body(kind, caster.internal.world, {1.0, 0.0, 0.0}, override)
        assert SpellRequirements.corpse(caster, spell) == nil
        Metadata.delete(guid)
      end
    end

    test "selects the nearest eligible body in the same copy", %{caster: caster, spell: spell} do
      body(:mob, WorldRef.instance(999, 202), {0.0, 0.0, 0.0})
      body(:mob, caster.internal.world, {0.0, 0.0, 5.81})
      assert SpellRequirements.corpse(caster, spell) == nil
      far = body(:mob, caster.internal.world, {0.0, 0.0, 5.77})
      assert %CorpseTarget{guid: ^far} = SpellRequirements.corpse(caster, spell)
      near = body(:mob, caster.internal.world, {1.0, 0.0, 0.0}, %{creature_type: 6})
      assert %CorpseTarget{guid: ^near} = SpellRequirements.corpse(caster, spell)
    end

    test "accepts unreleased players and released bodies without their owner online", %{caster: caster, spell: spell} do
      player = body(:player, caster.internal.world, {1.0, 0.0, 0.0})
      assert %CorpseTarget{guid: ^player, kind: :player} = SpellRequirements.corpse(caster, spell)
      Metadata.delete(player)
      corpse = body(:corpse, caster.internal.world, {1.0, 0.0, 0.0}, %{owner: player})
      assert %CorpseTarget{guid: ^corpse, kind: :corpse} = SpellRequirements.corpse(caster, spell)
    end

    test "corpse owners retain faction after the player leaves", %{caster: caster, spell: spell} do
      for {faction, edible?} <- [{friendly(), false}, {enemy(), true}] do
        owner = Guid.from_low_guid(:player, System.unique_integer([:positive]) + 82_000_000)
        Metadata.put(owner, %{faction_template: faction, faction_template_id: faction.id})

        corpse = %Corpse{
          object: %Object{guid: Corpse.guid_for(owner)},
          corpse: %CorpseComponent{owner: owner},
          movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}},
          internal: %Internal{world: caster.internal.world}
        }

        {:ok, pid} = World.start_entity(corpse)
        on_exit(fn -> if Process.alive?(pid), do: World.stop_entity(pid) end)
        Metadata.delete(owner)
        assert Metadata.get(corpse.object.guid).faction_template == faction
        assert match?(%CorpseTarget{}, SpellRequirements.corpse(caster, spell)) == edible?
        World.stop_entity(pid)
      end
    end
  end

  describe "cast_result/3" do
    test "uses the nearby body instead of validating the caster as an edible target", %{caster: caster, spell: spell} do
      :ets.insert(SpellLoader, {{:spell, 20_578}, nil})
      on_exit(fn -> :ets.delete(SpellLoader, {:spell, 20_578}) end)
      body(:mob, caster.internal.world, {1.0, 0.0, 0.0})
      state = %State{guid: caster.object.guid, character: caster}
      assert {:ok, _state} = Spellcasting.cast_result(state, spell, <<0::little-size(16)>>)
      refute_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 2}}}
    end

    test "rejects missing bodies without cooldown and preserves an existing cooldown", %{caster: caster, spell: spell} do
      state = %State{guid: caster.object.guid, character: caster}
      assert {:error, failed} = Spellcasting.cast_result(state, spell, <<0::little-size(16)>>)
      assert failed.character.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x86}}}
      assert_received {:"$gen_cast", {:send_packet, %SmsgClearCooldown{spell_id: 20_577}}}

      character = Cooldowns.start(caster, spell, Time.now())
      assert {:error, failed} = Spellcasting.cast_result(%{state | character: character}, spell, <<0::little-size(16)>>)
      assert failed.character.internal.cooldowns == character.internal.cooldowns
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x3C}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgClearCooldown{}}}
    end
  end

  describe "complete/2" do
    test "rejects a target that leaves launch range without paying costs", %{caster: caster} do
      spell = %{facing_spell() | custom_flags: 0}
      target = body(:mob, caster.internal.world, {30.0, 0.0, 0.0}, %{alive?: true})
      started = Casting.start(caster, spell, Target.unit(target), 1_000)
      SpatialHash.update(:mobs, target, caster.internal.world, 36.26, 0.0, 0.0)
      failed = started |> Casting.complete(3_000) |> EventSink.emit_pending(Context.new(self()))

      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      packet = SmsgCastResult.failure(spell, :out_of_range)
      assert_received {:"$gen_cast", {:send_packet, ^packet}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}
    end

    test "allows a target to move within launch grace", %{caster: caster} do
      spell = %{facing_spell() | custom_flags: 0}
      target = body(:mob, caster.internal.world, {30.0, 0.0, 0.0}, %{alive?: true})
      started = Casting.start(caster, spell, Target.unit(target), 1_000)
      SpatialHash.update(:mobs, target, caster.internal.world, 36.25, 0.0, 0.0)
      completed = started |> Casting.complete(3_000) |> EventSink.emit_pending(Context.new(self()))

      assert completed.internal.casting == nil
      assert completed.unit.power1 == 90
      assert Map.has_key?(completed.internal.cooldowns, spell.id)
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}
    end

    test "rejects targets that die, disappear, or become friendly during the cast", %{caster: caster} do
      spell = facing_spell()

      for {change, reason} <- [{:death, :targets_dead}, {:despawn, :bad_targets}, {:friendly, :target_friendly}] do
        target = body(:mob, caster.internal.world, {10.0, 0.0, 0.0}, %{alive?: true})
        started = Casting.start(caster, spell, Target.unit(target), 1_000)

        case change do
          :death -> Metadata.update(target, %{alive?: false})
          :despawn -> Metadata.delete(target)
          :friendly -> Metadata.update(target, %{faction_template: friendly()})
        end

        failed = started |> Casting.complete(3_000) |> EventSink.emit_pending(Context.new(self()))
        assert failed.internal.casting == nil
        assert failed.unit.power1 == 100
        assert failed.internal.cooldowns == %{}
        packet = SmsgCastResult.failure(spell, reason)
        assert_received {:"$gen_cast", {:send_packet, ^packet}}
        refute_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}
      end
    end

    test "turning away during a cast rejects launch without spending power or starting cooldown", %{caster: caster} do
      spell = facing_spell()
      target = body(:mob, caster.internal.world, {10.0, 0.0, 0.0}, %{alive?: true})
      started = Casting.start(caster, spell, Target.unit(target), 1_000)
      turned = %{started | movement_block: %{started.movement_block | position: {0.0, 0.0, 0.0, :math.pi()}}}
      failed = turned |> Casting.complete(3_000) |> EventSink.emit_pending(Context.new(self()))

      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x7C}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}

      retried = Casting.start(%{failed | movement_block: caster.movement_block}, spell, Target.unit(target), 4_000)

      completed = retried |> Casting.complete(6_000) |> EventSink.emit_pending(Context.new(self()))
      assert completed.internal.casting == nil
      assert completed.unit.power1 == 90
      assert Map.has_key?(completed.internal.cooldowns, spell.id)
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}
    end

    test "launch uses the target's latest position and orientation", %{caster: caster} do
      spell = facing_spell()
      target = body(:mob, caster.internal.world, {10.0, 0.0, 0.0}, %{alive?: true, orientation: 0.0})
      started = Casting.start(caster, spell, Target.unit(target), 1_000)
      SpatialHash.update(:mobs, target, caster.internal.world, -10.0, 0.0, 0.0)
      Metadata.update(target, %{orientation: 1.0})
      snapshot = SpellRequirements.resolve(caster, spell, Target.unit(target))
      assert snapshot.cast_target.info.position == {caster.internal.world, -10.0, 0.0, 0.0}
      assert snapshot.cast_target.info.orientation == 1.0

      failed = started |> Casting.complete(3_000) |> EventSink.emit_pending(Context.new(self()))
      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x7C}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgCastResult{result: 0}}}
    end

    test "lost corpses reject launch before costs or cooldown", %{caster: caster, spell: spell} do
      guid = body(:mob, caster.internal.world, {1.0, 0.0, 0.0})
      assert %CorpseTarget{} = SpellRequirements.corpse(caster, spell)
      casting = Casting.start(caster, spell, Target.self(caster.object.guid), 1_000)
      Metadata.delete(guid)
      failed = casting |> Casting.complete(1_000) |> EventSink.emit_pending(Context.new(self()))
      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %SmsgCastResult{reason: 0x86}}}
      assert_received {:"$gen_cast", {:send_packet, %SmsgClearCooldown{spell_id: 20_577}}}
    end

    test "eligible bodies allow the recovery trigger and retain the root cooldown", %{caster: caster, spell: spell} do
      body(:mob, caster.internal.world, {1.0, 0.0, 0.0})
      casting = caster |> Casting.start(spell, Target.self(caster.object.guid), 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      requirements = SpellRequirements.resolve(caster, spell)
      completed = Casting.resolve_requirements(casting, cast, requirements, 1_000)
      assert completed.internal.casting == nil
      assert completed.unit.power1 == 90
      assert Map.has_key?(completed.internal.cooldowns, spell.id)
      assert Enum.any?(completed.internal.events, &match?(%Effects.TriggerSpell{spell_id: 20_578}, &1))
    end
  end

  defp facing_spell do
    %Spell{
      id: 900_781,
      custom_flags: 0x80,
      cast_time_ms: 2_000,
      mana_cost: 10,
      power_type: 0,
      school: :fire,
      range_yards: 30.0,
      recovery_time_ms: 60_000,
      attributes: MapSet.new([:ignore_line_of_sight]),
      effects: [%Effect{index: 0, type: :school_damage, implicit_target_a: :target_enemy, base_points: 10}]
    }
  end

  defp caster(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]) + 81_000_000)
    Metadata.put(guid, %{faction_template: friendly()})
    on_exit(fn -> Metadata.delete(guid) end)

    caster = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 1_000, power1: 100, max_power1: 100, level: 50, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.instance(999, 201)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 20_577,
      script_name: "spell_cannibalize",
      mana_cost: 10,
      target_creature_type_mask: 96,
      power_type: 0,
      range_yards: 5.0,
      recovery_time_ms: 120_000
    }

    %{caster: caster, spell: spell}
  end

  defp body(kind, world, {x, y, z}, overrides \\ %{}) do
    guid =
      if kind == :mob,
        do: Guid.runtime(:mob, 1),
        else: Guid.from_low_guid(kind, System.unique_integer([:positive]) + 81_000_000)

    table = %{mob: :mobs, player: :players, corpse: :corpses}[kind]
    SpatialHash.update(table, guid, world, x, y, z)

    Metadata.put(
      guid,
      Map.merge(%{alive?: false, ghost?: false, faction_template: enemy(), creature_type: 7, unit_flags: 0}, overrides)
    )

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp friendly, do: %FactionTemplate{id: 1, faction: 1, faction_group: 1, friend_group: 1, enemy_group: 2}
  defp enemy, do: %FactionTemplate{id: 2, faction: 2, faction_group: 2, friend_group: 2, enemy_group: 1}
end
