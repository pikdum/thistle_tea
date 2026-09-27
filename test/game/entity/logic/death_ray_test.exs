defmodule ThistleTea.Game.Entity.Logic.DeathRayTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engineering.DeathRay
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:caster]

  describe "start/5" do
    test "self-targeted activation charges once at channel start", %{caster: caster} do
      caster = %{caster | internal: %{caster.internal | casting: nil}}
      caster = Casting.start(caster, channel(), Target.self(1), 0)
      assert caster.internal.casting && caster.internal.casting.phase == :channel_tick, inspect(caster.internal.events)

      assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 13_493}] =
               triggers(caster.internal.events)

      caster = %{caster | internal: %{caster.internal | events: []}}
      assert {:waiting, caster, _delay} = Casting.advance(caster, 1_000)
      assert triggers(caster.internal.events) == []
    end
  end

  describe "aura_amount/2" do
    test "rolls within the reference range once per application", %{caster: caster} do
      assert DeathRay.aura_amount(periodic(), fn 401 -> 1 end) == 100
      assert DeathRay.aura_amount(periodic(), fn 401 -> 401 end) == 500
      assert DeathRay.aura_amount(%Spell{id: 1}, fn _ -> flunk("unexpected random roll") end) == nil
      {caster, _} = Aura.apply_spell(caster, 1, 60, periodic(), 0)
      assert hd(hd(caster.unit.auras).auras).amount in 100..500
    end
  end

  describe "tick/2" do
    test "delayed delivery preserves the final tick before the channel ends", %{caster: caster} do
      caster = %{caster | internal: %{caster.internal | casting: nil}}
      caster = Casting.start(caster, channel(), Target.self(1), 0)
      {caster, _} = Aura.apply_spell(caster, 1, 60, periodic(), 14)
      [holder] = caster.unit.auras
      amount = hd(holder.auras).amount
      assert holder.applied_at == 0
      assert holder.expires_at == caster.internal.casting.ends_at

      {caster, events} =
        Enum.reduce(1..4, {caster, []}, fn tick, {current, previous} ->
          {current, events} = Aura.tick(current, tick * 1_000)
          {current, previous ++ events}
        end)

      assert caster.unit.health == 5_000 - 4 * amount
      assert [discharge] = triggers(events)
      assert discharge.amount == 4 * amount
      assert {:finished, caster} = Casting.advance(caster, 4_000)
      assert caster.internal.casting == nil
      assert caster.unit.auras == []
    end

    test "four ticks discharge their accumulated base amount once", %{caster: caster} do
      caster = charge(caster)

      {caster, events} =
        Enum.reduce(1..4, {caster, []}, fn tick, {current, previous} ->
          {current, events} = Aura.tick(current, tick * 1_000)
          assert current.unit.health == 5_000 - tick * 200
          assert [%Effects.SpellDamage{damage: 200}] = damage_events(events)
          {current, previous ++ events}
        end)

      assert caster.unit.auras == []
      assert [%Effects.TriggerSpell{spell_id: 13_279, target_guid: 2, amount: 800, slot: 0}] = triggers(events)
      assert {^caster, []} = Aura.tick(caster, 5_000)
    end

    test "interruption stops charging and releases only the partial charge at expiry", %{caster: caster} do
      {caster, _} = caster |> charge() |> Aura.tick(1_000)
      caster = Casting.cancel(caster, 1_500)
      assert caster.internal.casting == nil
      assert [%Holder{spell: %{id: 13_493}}] = caster.unit.auras

      {caster, events} = Aura.tick(caster, 2_000)
      assert caster.unit.health == 4_800
      assert triggers(events) == []
      {caster, events} = Aura.tick(caster, 4_000)
      assert caster.unit.health == 4_800
      assert [%Effects.TriggerSpell{amount: 200}] = triggers(events)
      assert caster.unit.auras == []
    end

    test "a different spell and an unstarted channel do not charge", %{caster: caster} do
      for cast <- [
            nil,
            %{caster.internal.casting | phase: :preparing},
            %{caster.internal.casting | spell: %Spell{id: 1}}
          ] do
        caster = %{charge(caster) | internal: %{caster.internal | casting: cast}}
        {caster, events} = Aura.tick(caster, 4_000)
        assert caster.unit.health == 5_000
        assert triggers(events) == []
        assert caster.unit.auras == []
      end
    end

    test "expiry uses the current selection and needs a target", %{caster: caster} do
      for target <- [0, 3] do
        caster = charge(caster)
        caster = %{caster | unit: %{caster.unit | target: target}}
        {_caster, events} = Aura.tick(caster, 4_000)

        if target == 0,
          do: assert(triggers(events) == []),
          else: assert([%Effects.TriggerSpell{target_guid: 3, requires_living_target?: true}] = triggers(events))
      end
    end

    test "absorption spends the shield without erasing the accumulated base damage", %{caster: caster} do
      caster = charge(caster)

      shield = %Holder{
        spell: %Spell{id: 10},
        auras: [%AuraData{index: 0, type: :school_absorb, misc_value: 64, amount: 250}]
      }

      caster = %{caster | unit: %{caster.unit | auras: [shield | caster.unit.auras]}}
      {caster, events} = Aura.tick(caster, 1_000)
      assert [%Effects.SpellDamage{damage: 200, absorbed: 200}] = damage_events(events)
      assert caster.unit.health == 5_000
      assert hd(hd(caster.unit.auras).auras).amount == 50
      {caster, events} = Aura.tick(caster, 4_000)
      assert caster.unit.health == 4_850
      assert [%Effects.TriggerSpell{amount: 400}] = triggers(events)
      assert caster.unit.auras == []
    end

    test "school immunity prevents both self damage and accumulation", %{caster: caster} do
      caster = charge(caster)
      immune = %Holder{spell: %Spell{id: 10}, auras: [%AuraData{type: :school_immunity, misc_value: 64}]}
      caster = %{caster | unit: %{caster.unit | auras: [immune | caster.unit.auras]}}
      {caster, events} = Aura.tick(caster, 4_000)
      assert caster.unit.health == 5_000
      assert [%Effects.SpellDamageImmune{}] = Enum.filter(events, &is_struct(&1, Effects.SpellDamageImmune))
      assert triggers(events) == []
    end

    test "death and manual removal discard the charge", %{caster: caster} do
      {caster, _} = caster |> charge() |> Aura.tick(1_000)
      dead = Core.take_damage(caster, 10_000, 1_500)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
      assert triggers(dead.internal.events) == []
      assert {_dead, []} = Aura.tick(dead, 4_000)

      {removed, events} = Aura.remove_spells(caster, [13_493], 1_500)
      assert triggers(events) == []
      assert {^removed, []} = Aura.tick(removed, 4_000)
    end

    test "lethal charging damage cannot fire a discharge", %{caster: caster} do
      caster = charge(%{caster | unit: %{caster.unit | health: 100}})
      {dead, events} = Aura.tick(caster, 4_000)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
      assert triggers(events) == []
    end

    test "refresh starts a fresh charge", %{caster: caster} do
      {caster, _} = caster |> charge() |> Aura.tick(1_000)
      {caster, _} = Aura.apply_spell(caster, 1, 60, periodic(), 1_500)
      assert hd(hd(caster.unit.auras).auras).accumulated_damage == 0
    end
  end

  defp triggers(events), do: Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
  defp damage_events(events), do: Enum.filter(events, &is_struct(&1, Effects.SpellDamage))

  defp charge(caster) do
    {caster, _} = Aura.apply_spell(caster, 1, 60, periodic(), 0)
    [holder] = caster.unit.auras
    [aura] = holder.auras
    %{caster | unit: %{caster.unit | auras: [%{holder | auras: [%{aura | amount: 200}]}]}}
  end

  defp caster(_context) do
    cast = %{Cast.new(channel(), Target.unit(2), 0) | phase: :channel_tick}

    %{
      caster: %Character{
        object: %Object{guid: 1},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        player: %Player{},
        unit: %Unit{health: 5_000, max_health: 5_000, level: 60, target: 2, auras: []},
        internal: %Internal{casting: cast, events: []}
      }
    }
  end

  defp channel do
    %Spell{
      id: 13_278,
      script_name: "spell_gdr_channel",
      duration_ms: 4_000,
      attributes: MapSet.new([:channeled]),
      effects: [%Effect{index: 1, type: :dummy, implicit_target_a: :target_enemy}]
    }
  end

  defp periodic do
    %Spell{
      id: 13_493,
      script_name: "spell_gdr_periodic",
      school: :arcane,
      duration_ms: 4_000,
      attributes: MapSet.new([:ignore_caster_modifiers]),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :periodic_damage,
          amplitude_ms: 1_000,
          base_points: 149,
          base_dice: 1,
          implicit_target_a: :caster
        }
      ]
    }
  end
end
