defmodule ThistleTea.Game.Entity.Logic.KillFeedbackDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.KillFeedback
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db

  setup [:catalog, :entities]

  describe "receive/3" do
    test "Spirit Tap doubles spirit after a killing blow and restores it on expiry", %{caster: caster, victim: victim} do
      caster = with_aura(caster, 15_338)
      caster = caster |> feedback(victim) |> resolve_proc(15_271)
      assert caster.unit.spirit == 100
      assert Enum.any?(caster.unit.auras, &(&1.spell.id == 15_271))
      {caster, _events} = Aura.expire_due(caster, 15_000)
      assert caster.unit.spirit == 50
      refute Enum.any?(caster.unit.auras, &(&1.spell.id == 15_271))
    end

    test "Remorseless Attacks and Spinal Reaper use their DBC kill triggers", %{caster: caster, victim: victim} do
      for {talent, trigger} <- [{14_144, 14_143}, {14_148, 14_149}, {21_185, 21_186}] do
        caster = caster |> with_aura(talent) |> feedback(victim)
        assert Enum.any?(caster.internal.events, &match?(%Effects.TriggerSpell{spell_id: ^trigger}, &1))
      end
    end

    test "Improved Drain Soul raises its zero base proc chance through spell modifiers", %{
      caster: caster,
      victim: victim
    } do
      drain = SpellLoader.load(1120)
      assert drain.proc_chance == 0

      for {talent, chance} <- [{18_213, 50}, {18_372, 100}] do
        caster = with_aura(caster, talent)
        modifier = &Modifiers.value(caster, drain, :chance_of_success, &1)
        assert modifier.(0) == chance
        assert Proc.roll?(drain, nil, fn -> chance / 100 end, modifier)
        refute Proc.roll?(drain, nil, fn -> 1.0 end, fn _ -> 0 end)
      end

      caster = with_aura(caster, 18_372)
      context = CastContext.from_caster(caster, drain, caster.object.guid)
      {caster, _events} = SpellEffect.receive(caster, context, drain, 0)
      assert Enum.any?(caster.unit.auras, &(&1.spell.id == 1120 and &1.charges == 1))
      caster = feedback(caster, victim)
      refute Enum.any?(caster.unit.auras, &(&1.spell.id == 1120))
      caster = resolve_proc(caster, 18_371)
      assert Enum.any?(caster.unit.auras, &(&1.spell.id == 18_371))
      {caster, _events} = Aura.expire_due(caster, 10_000)
      refute Enum.any?(caster.unit.auras, &(&1.spell.id == 18_371))
    end

    test "untalented and canceled Drain Soul cannot proc Soul Siphon", %{caster: caster, victim: victim} do
      drain = SpellLoader.load(1120)
      context = CastContext.from_caster(caster, drain, caster.object.guid)
      {caster, _events} = SpellEffect.receive(caster, context, drain, 0)
      refute Enum.any?(feedback(caster, victim).internal.events, &match?(%Effects.TriggerSpell{spell_id: 18_371}, &1))

      caster = with_aura(caster, 18_372)
      {caster, _events} = Aura.remove_spells(caster, [1120], 1)
      refute Enum.any?(feedback(caster, victim).internal.events, &match?(%Effects.TriggerSpell{spell_id: 18_371}, &1))
    end
  end

  defp feedback(caster, victim) do
    dead = Core.take_damage(victim, 100, 0, source: caster.object.guid)
    event = Enum.find(dead.internal.events, &is_struct(&1, Effects.KillOutcome))
    KillFeedback.receive(caster, event.victim, 0)
  end

  defp resolve_proc(caster, id) do
    {caster, events} = Effects.drain(caster)
    trigger = Enum.find(events, &match?(%Effects.TriggerSpell{spell_id: ^id}, &1))
    assert trigger
    delivery = caster |> Spells.resolve(trigger) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
    assert delivery.target_guid == caster.object.guid
    {caster, _events} = SpellEffect.receive(caster, delivery.cast_context, delivery.spell, 0)
    caster
  end

  defp with_aura(caster, id) do
    {caster, _events} = Aura.apply_spell(caster, caster.object.guid, 60, SpellLoader.load(id), 0)
    caster
  end

  defp catalog(_context) do
    for id <- [15_338, 15_271, 14_144, 14_143, 14_148, 14_149, 21_185, 21_186, 18_213, 18_372, 18_371, 1120] do
      key = {:chain, id}
      previous = :ets.lookup(SpellChain, key)
      :ets.insert(SpellChain, {key, nil})

      on_exit(fn ->
        :ets.delete(SpellChain, key)
        :ets.insert(SpellChain, previous)
      end)
    end

    :ok
  end

  defp entities(_context) do
    unit = %Unit{level: 60, health: 100, max_health: 100, base_spirit: 50, power1: 0, max_power1: 1_000, auras: []}
    caster = %Character{object: %Object{guid: 1}, unit: Stats.recompute(unit), player: %Player{}, internal: %Internal{}}

    victim = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: unit,
      internal: %Internal{creature: %Creature{experience_multiplier: 1.0}}
    }

    %{caster: caster, victim: victim}
  end
end
