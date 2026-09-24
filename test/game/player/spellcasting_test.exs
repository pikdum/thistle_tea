defmodule ThistleTea.Game.Player.SpellcastingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "charm_cast/2" do
    setup [:script_caster]

    test "starts learned casts and retains death and resource validation", %{state: state, spell: spell} do
      controller = Guid.from_low_guid(:mob, 1, state.guid)
      target = state.guid + 1_000_000
      world = state.character.internal.world
      enemy = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
      friendly = %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}
      Metadata.put(controller, %{alive?: true, in_combat: true, faction_template: enemy})
      Metadata.put(state.guid, %{alive?: true, owner_guid: controller, faction_template: enemy})
      Metadata.put(target, %{alive?: true, faction_template: friendly, unit_flags: 8})
      SpatialHash.update(:mobs, controller, world, 0.0, 0.0, 0.0)
      SpatialHash.update(:players, target, world, 5.0, 0.0, 0.0)

      on_exit(fn ->
        Enum.each([state.guid, controller, target], &Metadata.delete/1)
        SpatialHash.remove(:mobs, controller)
        SpatialHash.remove(:players, target)
      end)

      spell = %{
        spell
        | attributes: MapSet.new([:ignore_line_of_sight]),
          effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      }

      control = %Possession{
        caster_guid: controller,
        spell_id: 28_410,
        applied_at: 1,
        original_faction_template: 1,
        kind: :charm,
        spells: [spell]
      }

      character = state.character

      character = %{
        character
        | unit: %{character.unit | target: target},
          internal: %{character.internal | possession: control, spellbook: %{spell.id => spell}}
      }

      state = %{state | ready: true, character: character}

      effect = %Effects.CharmCast{
        controller_guid: controller,
        control_spell_id: 28_410,
        control_applied_at: 1,
        spell_id: spell.id,
        target_guid: target
      }

      cast = Spellcasting.charm_cast(state, effect)
      assert %Cast{spell: ^spell} = cast.character.internal.casting
      assert Target.unit_guid(cast.character.internal.casting.targets) == target
      assert_receive :player_tick

      for unit <- [%{character.unit | health: 0}, %{character.unit | power1: 0}] do
        rejected = %{state | character: %{character | unit: unit}}
        assert Spellcasting.charm_cast(rejected, effect) == rejected
      end

      cancelled = %{state | character: PlayerCharm.command(character, :passive, 0, Time.now())}
      assert Spellcasting.charm_cast(cancelled, effect) == cancelled
      Metadata.update(controller, %{in_combat: false})
      assert Spellcasting.charm_cast(state, effect) == state
    end
  end

  describe "cast_result/3" do
    setup [:script_caster]

    test "rejects a visible stealth opener with its protocol error and no resource loss", %{state: state, spell: spell} do
      spell = %{spell | attributes: MapSet.new([:only_stealthed])}
      assert {:error, rejected} = Spellcasting.cast_result(state, spell, <<0::16>>)
      assert rejected.character.internal.casting == nil
      assert rejected.character.internal.cooldowns == %{}
      assert rejected.character.unit.power1 == state.character.unit.power1
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: id, reason: 0x57}}}
      assert id == spell.id
    end
  end

  describe "scripted_cast/4" do
    setup [:script_caster]

    test "rejects shapeshift-sensitive auras using the recipient's published form", %{
      state: state,
      spell: spell,
      entry: entry
    } do
      guid = Guid.from_low_guid(:mob, 4952, System.unique_integer([:positive]))
      Metadata.put(guid, %{alive?: true, shapeshift_form: 1})
      on_exit(fn -> Metadata.delete(guid) end)

      spell = %{
        spell
        | aura_interrupt_flags: 0x8000,
          effects: [%Effect{type: :apply_aura, aura: :water_walk, implicit_target_a: :any_unit}],
          attributes: MapSet.new([:ignore_line_of_sight])
      }

      rejected = Spellcasting.scripted_cast(state, spell, entry, guid)
      assert rejected.character.internal.casting == nil
      assert rejected.character.unit.power1 == state.character.unit.power1
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 2}}}

      Metadata.update(guid, %{shapeshift_form: 31})
      allowed = Spellcasting.scripted_cast(state, spell, entry, guid)
      assert allowed.character.internal.casting.spell.id == spell.id
    end

    test "any-unit casts receive template immunity from metadata", %{state: state, spell: spell, entry: entry} do
      guid = Guid.from_low_guid(:mob, 4952, System.unique_integer([:positive]))
      Metadata.put(guid, %{alive?: true, unit_flags: 0})
      on_exit(fn -> Metadata.delete(guid) end)

      spell = %{
        spell
        | effects: [%Effect{type: :instakill, implicit_target_a: :any_unit}],
          attributes: MapSet.new([:ignore_line_of_sight])
      }

      allowed = Spellcasting.scripted_cast(state, spell, entry, guid)
      assert allowed.character.internal.casting.spell.id == spell.id

      Metadata.update(guid, %{unit_flags: 0x100})
      rejected = Spellcasting.scripted_cast(state, spell, entry, guid)
      assert rejected.character.internal.casting == nil
      assert rejected.character.unit.power1 == state.character.unit.power1
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 2}}}
    end

    test "starts an unlearned script spell with its real cast time", %{state: state, spell: spell, entry: entry} do
      cast_state = Spellcasting.scripted_cast(state, spell, entry, state.guid)
      assert %Cast{spell: ^spell} = cast_state.character.internal.casting
      assert Target.unit_guid(cast_state.character.internal.casting.targets) == state.guid
      assert cast_state.character.internal.spellbook == %{}
      assert is_reference(cast_state.player_tick_ref)
      assert_receive :player_tick
    end

    test "preserves a busy cast unless the script interrupts it", %{state: state, spell: spell, entry: entry} do
      previous = %{spell | id: spell.id + 1}
      character = Casting.start(state.character, previous, Target.unit(state.guid), Time.now())
      state = %{state | character: character}
      assert Spellcasting.scripted_cast(state, spell, entry, state.guid) == state
      entry = %{entry | cast_flags: MapSet.new([:interrupt_previous])}
      interrupted = Spellcasting.scripted_cast(state, spell, entry, state.guid)
      assert interrupted.character.internal.casting.spell == spell
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{spell: old_id}}}
      assert old_id == previous.id
      assert_receive :player_tick
    end

    test "retains player death and resource validation", %{state: state, spell: spell, entry: entry} do
      for unit <- [%{state.character.unit | health: 0}, %{state.character.unit | power1: 0}] do
        state = %{state | character: %{state.character | unit: unit}}
        rejected = Spellcasting.scripted_cast(state, spell, entry, state.guid)
        assert rejected.character.internal.casting == nil
        assert rejected.character.unit.power1 == unit.power1
        assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 2}}}
      end
    end
  end

  defp script_caster(_context) do
    guid = System.unique_integer([:positive, :monotonic])

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 50, health: 100, max_health: 100, power1: 100, max_power1: 100, power_type: 0},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }

    spell = %Spell{id: 999_001, name: "Script Cast", school: :holy, cast_time_ms: 1_500, power_type: 0, mana_cost: 10}

    %{
      state: %State{guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character},
      spell: spell,
      entry: %CreatureSpell{spell_id: spell.id}
    }
  end

  describe "complete/1" do
    test "schedules the repeat loop after Auto Shot activates" do
      character = %Character{
        unit: %Unit{health: 100, max_health: 100},
        internal: %Internal{auto_shot: %{target_guid: 42}}
      }

      state = Spellcasting.complete(%{character: character, player_tick_ref: nil})

      assert is_reference(state.player_tick_ref)
      assert_receive :player_tick
    end
  end
end
