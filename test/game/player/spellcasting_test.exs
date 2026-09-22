defmodule ThistleTea.Game.Player.SpellcastingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Logic.Casting
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
  alias ThistleTea.Game.WorldRef

  describe "scripted_cast/4" do
    setup [:script_caster]

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
