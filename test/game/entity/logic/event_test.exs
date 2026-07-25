defmodule ThistleTea.Game.Entity.Logic.EffectsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target

  describe "monster_move/1" do
    test "returns a monster movement event with packet options" do
      assert %Effects.MonsterMove{move_opts: [face_target: 1]} = Effects.monster_move(face_target: 1)
    end
  end

  describe "spell_cast_result/1" do
    test "returns a spell cast result event" do
      assert %Effects.SpellCastResult{spell_id: 133} = Effects.spell_cast_result(133)
    end
  end

  describe "spell_go/4" do
    test "returns a spell go event with resolved hits and semantic targets" do
      target = Target.unit(2)

      assert %Effects.SpellGo{source_guid: 1, spell_id: 133, hit_guids: [2], targets: ^target} =
               Effects.spell_go(1, 133, [2], target)
    end
  end

  describe "channel_start/3" do
    test "returns a channel start event" do
      assert %Effects.ChannelStart{source_guid: 1, spell_id: 10, channel_time_ms: 8_000} =
               Effects.channel_start(1, 10, 8_000)
    end
  end

  describe "channel_update/2" do
    test "returns a channel update event" do
      assert %Effects.ChannelUpdate{source_guid: 1, channel_time_ms: 0} = Effects.channel_update(1, 0)
    end
  end

  describe "deliver_attack/2" do
    test "returns an attack delivery event" do
      attack = %{caster: 1, min_damage: 2, max_damage: 3}

      assert %Effects.DeliverAttack{target_guid: 2, attack: ^attack} = Effects.deliver_attack(2, attack)
    end
  end

  describe "deliver_spell/3" do
    test "returns a spell delivery event" do
      context = %CastContext{caster_guid: 1, target_guid: 2}
      spell = %Spell{id: 133}

      assert %Effects.DeliverSpell{target_guid: 2, cast_context: ^context, spell: ^spell} =
               Effects.deliver_spell(2, context, spell)
    end
  end
end
