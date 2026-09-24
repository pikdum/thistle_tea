defmodule ThistleTea.Game.Entity.Logic.CastSpeedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  describe "recompute/1" do
    test "independent haste and slow effects multiply without drift" do
      unit = %Unit{auras: [holder(1, 20), holder(2, 25), holder(3, -50)]}
      derived = Stats.recompute(unit)
      assert_in_delta derived.mod_cast_speed, 1.0, 0.00001
      assert Stats.recompute(derived) == derived
      assert Stats.recompute(%{derived | auras: []}).mod_cast_speed == 1.0
    end

    test "stacks change the holder amount before calculating its factor" do
      unit = %Unit{auras: [%{holder(1, -20) | stacks: 3}]}
      assert Stats.recompute(unit).mod_cast_speed == 1.6
    end
  end

  describe "start/5" do
    test "the cast and client field use the same aura multiplier after family modifiers" do
      modifier = %Holder{
        spell: %Spell{id: 2, spell_family: 3},
        auras: [%Aura{type: :add_flat_modifier, amount: -500, misc_value: 10, class_mask: 1}]
      }

      caster = caster([holder(1, -50), modifier])
      spell = %Spell{id: 686, spell_family: 3, family_flags_0: 1, cast_time_ms: 2_500}
      result = Casting.start(caster, spell, Target.none(), 1_000)
      assert result.unit.mod_cast_speed == 1.5

      for audience <- [:self, :other] do
        field = result.unit |> Unit.to_list(audience) |> List.keyfind(:mod_cast_speed, 0)
        assert UpdateObject.field(field) == <<1.5::little-float-size(32)>>
      end

      assert result.internal.casting.cast_time_ms == 3_000
      assert result.internal.casting.ends_at == 4_000
    end

    test "abilities and professions ignore spell haste while ranged abilities use weapon haste" do
      caster = caster([holder(1, 100), holder(2, 25, :mod_ranged_haste)])

      for {attributes, dmg_class, expected} <- [
            {[], 1, 1_000},
            {[:ability], 2, 2_000},
            {[:tradeskill], 0, 2_000},
            {[:ability, :uses_ranged_slot], 3, 1_600}
          ] do
        spell = %Spell{id: 1, attributes: MapSet.new(attributes), dmg_class: dmg_class, cast_time_ms: 2_000}
        result = Casting.start(caster, spell, Target.none(), 1_000)
        assert result.internal.casting.cast_time_ms == expected
      end
    end

    test "haste shifts the channel start without shortening its ticks or duration" do
      spell = %Spell{
        id: 1,
        cast_time_ms: 2_000,
        duration_ms: 6_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{amplitude_ms: 2_000}]
      }

      result = Casting.start(caster([holder(1, 100)]), spell, Target.none(), 1_000)
      assert result.internal.casting.cast_time_ms == 1_000
      assert result.internal.casting.channel_ms == 6_000
      assert result.internal.casting.channel_tick_ms == 2_000
      assert result.internal.casting.next_channel_tick_at == 4_000
      assert result.internal.casting.ends_at == 8_000
    end
  end

  describe "expire_due/2" do
    test "expiry restores the projection and subsequent casts without changing an active cast" do
      caster = caster([%{holder(1, -50) | expires_at: 2_000}])
      spell = %Spell{id: 2, cast_time_ms: 2_000}
      casting = Casting.start(caster, spell, Target.none(), 1_000)
      {expired, _events} = AuraLogic.expire_due(casting, 2_000)
      assert expired.unit.mod_cast_speed == 1.0
      assert expired.internal.broadcast_update?
      assert expired.internal.casting == casting.internal.casting

      next = Casting.start(expired, spell, Target.none(), 5_000)
      assert next.internal.casting.cast_time_ms == 2_000
    end
  end

  defp caster(auras) do
    %Mob{
      object: %Object{guid: 1},
      unit: Stats.recompute(%Unit{level: 60, auras: auras}),
      internal: %Internal{}
    }
  end

  defp holder(id, amount, type \\ :mod_casting_speed) do
    %Holder{spell: %Spell{id: id}, caster_guid: 1, auras: [%Aura{type: type, amount: amount}]}
  end
end
