defmodule ThistleTea.Game.World.Loader.PeriodicModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:improved_fire_totem_masks]

  describe "load/1" do
    test "both Improved Fire Totems ranks shorten each Fire Nova rank to one explosion" do
      for {talent_id, period, duration} <- [{nil, 4_000, 5_000}, {16_086, 3_000, 4_000}, {16_544, 2_000, 3_000}],
          {summon_id, aura_id} <- [{1535, 8443}, {8498, 8504}, {8499, 8505}, {11_314, 11_310}, {11_315, 11_311}] do
        owner = owner(talent_id)
        summon = SpellLoader.load(summon_id)
        context = %{CastContext.from_caster(owner, summon, 1) | target_role: :caster}

        assert {_, [%Effects.SummonTotem{duration_ms: ^duration} = effect]} =
                 SpellEffect.receive(owner, context, summon, 1_000)

        ward =
          Totems.prepare(%{owner | object: %Object{guid: 2}, unit: %{owner.unit | auras: []}}, owner, effect, 1_000)

        assert ward.internal.totem.expires_at == 1_000 + duration
        periodic = SpellLoader.load(aura_id)
        context = CastContext.from_caster(ward, periodic, 2)
        {ward, _events} = Aura.apply_spell(ward, context, periodic, 1_000)
        assert [holder] = ward.unit.auras
        assert [aura] = holder.auras
        assert aura.amplitude_ms == period
        assert aura.next_tick_at == 1_000 + period
        assert holder.expires_at == -1
        {ward, events} = Aura.tick(ward, 1_000 + period)
        assert Enum.count(events, &is_struct(&1, Effects.TriggerSpell)) == 1
        assert Aura.next_event_at(ward) > ward.internal.totem.expires_at
      end
    end
  end

  defp owner(talent_id) do
    owner = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      internal: %Internal{}
    }

    if talent_id do
      {owner, _events} = Aura.apply_spell(owner, 1, 60, SpellLoader.load(talent_id), 0)
      owner
    else
      owner
    end
  end

  defp improved_fire_totem_masks(_context) do
    for id <- [16_086, 16_544] do
      key = {:class_masks, id}
      previous = :ets.lookup(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, {key, {32, 134_217_728, 4}})

      on_exit(fn ->
        :ets.delete(SpellEffectOverride, key)
        :ets.insert(SpellEffectOverride, previous)
      end)
    end

    :ok
  end
end
