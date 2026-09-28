defmodule ThistleTea.Game.Spell.SwiftmendDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName

  @moduletag :dbc_db
  @rejuvenation [774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25_299]
  @regrowth [8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858]

  setup [:spell_label, :recipient]

  describe "receive/4" do
    test "all Rejuvenation and Regrowth ranks support foreign-caster Swiftmend", context do
      swiftmend = SpellLoader.load(18_562)

      for {ids, ticks} <- [{@rejuvenation, 4}, {@regrowth, 6}], id <- ids do
        hot = SpellLoader.load(id)
        {recipient, _} = SpellEffect.receive(context.recipient, context.hot_cast, hot, 1_000)
        [holder] = recipient.unit.auras
        [aura] = Enum.filter(holder.auras, &(&1.type == :periodic_heal))
        assert aura.amplitude_ms == 3_000
        assert :ok = CastValidation.validate(recipient, swiftmend, Target.unit(1), :self, 2_000)

        {healed, events} = SpellEffect.receive(recipient, context.heal_cast, swiftmend, 2_000)
        assert healed.unit.health == recipient.unit.health + aura.amount * ticks + 1
        refute Aura.has_spell?(healed, id)
        assert Enum.any?(events, &match?(%Effects.SpellHeal{source_guid: 3, target_guid: 1, spell_id: 18_562}, &1))
        assert {:error, :target_aurastate} = CastValidation.validate(healed, swiftmend, Target.unit(1), :self, 2_001)
        assert {^healed, []} = SpellEffect.receive(healed, context.heal_cast, swiftmend, 2_001)
      end
    end

    test "expired real HoTs cannot supply a delayed heal", context do
      hot = SpellLoader.load(774)
      swiftmend = SpellLoader.load(18_562)
      {recipient, _} = SpellEffect.receive(context.recipient, context.hot_cast, hot, 1_000)
      [holder] = recipient.unit.auras
      assert {^recipient, []} = SpellEffect.receive(recipient, context.heal_cast, swiftmend, holder.expires_at)
      {expired, _} = Aura.tick(recipient, holder.expires_at + 1)
      refute Aura.has_spell?(expired, 774)
      assert {^expired, []} = SpellEffect.receive(expired, context.heal_cast, swiftmend, holder.expires_at + 2)
    end
  end

  defp spell_label(_context) do
    previous = :ets.lookup(SpellScriptName, 18_562)
    :ets.insert(SpellScriptName, {18_562, "spell_druid_swiftmend"})

    on_exit(fn ->
      :ets.delete(SpellScriptName, 18_562)
      :ets.insert(SpellScriptName, previous)
    end)
  end

  defp recipient(_context) do
    %{
      recipient: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 10_000, auras: []},
        player: %Player{},
        internal: %Internal{}
      },
      hot_cast: %CastContext{caster_guid: 2, caster_level: 60, target_guid: 1},
      heal_cast: %CastContext{caster_guid: 3, caster_level: 60, target_guid: 1}
    }
  end
end
