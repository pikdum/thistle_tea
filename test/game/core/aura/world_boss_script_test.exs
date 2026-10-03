defmodule ThistleTea.Game.Core.Aura.WorldBossScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @kazzak 12_397

  setup [:player]

  describe "Arcane Vacuum" do
    test "forgets the victim's threat and has Azuregos pull them in", %{player: player} do
      azuregos = Unique.integer()
      context = %CastContext{caster_guid: azuregos, caster_level: 63}
      vacuum = %Spell{id: 21_147, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :caster_area_enemy}]}

      assert {_player, [threat, summon]} = SpellEffect.receive(player, context, vacuum, 1_000)
      assert threat == Effects.modify_threat_percent(azuregos, -100)

      assert %Effects.TriggerSpell{source_guid: ^azuregos, spell_id: 21_150, resolve_targets?: true} = summon
      assert summon.target_guid == player.object.guid
    end
  end

  describe "Shadow Portal" do
    test "forgets the victim's threat and sends them to a random room", %{player: player} do
      gandling = Unique.integer()
      context = %CastContext{caster_guid: gandling, caster_level: 61}
      portal = %Spell{id: 17_950, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :target_enemy}]}

      assert {_player, [threat, %Effects.RandomChoice{choices: choices}]} =
               SpellEffect.receive(player, context, portal, 1_000)

      assert threat == Effects.modify_threat_percent(gandling, -100)
      assert Enum.map(choices, fn {1, [cast]} -> cast.spell_id end) == [17_863, 17_939, 17_943, 17_944, 17_946, 17_948]
      assert Enum.all?(choices, fn {1, [cast]} -> cast.source_guid == gandling and cast.resolve_targets? end)
    end
  end

  describe "Mark of Kazzak" do
    test "explodes and fades once its victim runs out of mana", %{player: player} do
      for {mana, explodes?} <- [{150, true}, {600, false}] do
        marked = mark_of_kazzak(%{player | unit: %{player.unit | power1: mana}})
        {after_tick, events} = Aura.tick(marked, 2_000)
        guid = player.object.guid

        assert after_tick.unit.power1 == max(mana - 250, 0)

        assert Enum.any?(events, &match?(%Effects.TriggerSpell{target_guid: ^guid, spell_id: 21_058}, &1)) ==
                 explodes?

        assert Enum.any?(events, &match?(%Effects.RemoveAura{source_guid: @kazzak, spell_id: 21_056}, &1)) ==
                 explodes?
      end
    end

    test "leaves players without mana marked", %{player: player} do
      rage = mark_of_kazzak(%{player | unit: %{player.unit | power_type: 1, power1: 0}})
      {_after_tick, events} = Aura.tick(rage, 2_000)
      refute Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 21_058}, &1))
    end
  end

  describe "Twisted Reflection" do
    setup %{player: player} do
      reflection =
        Semantics.compile(%Spell{
          id: 21_063,
          school: :shadow,
          duration_ms: 45_000,
          proc_type_mask: 664_232,
          proc_chance: 100,
          effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, implicit_target_a: :target_enemy}]
        })

      context = %CastContext{caster_guid: @kazzak, caster_level: 63}
      {reflected, _events} = Aura.apply_spell(player, context, reflection, 0)
      %{reflected: reflected}
    end

    test "heals whoever strikes the afflicted", %{player: player, reflected: reflected} do
      shadow_bolt = %Spell{id: 21_066, school: :shadow, dmg_class: 1, effects: [%Effect{type: :school_damage}]}

      for {event, proc_type, spell} <- [
            {:hit_taken, :take_melee_swing, nil},
            {:spell_hit_taken, :take_harmful_spell, shadow_bolt}
          ] do
        context = %{attacker_guid: @kazzak, spell: spell, proc_type: proc_type, outcome: :normal, damage: 500, now: 1}
        {_reflected, events} = Aura.reactions(reflected, event, context)
        guid = player.object.guid

        assert [%Effects.TriggerSpell{source_guid: ^guid, target_guid: @kazzak, spell_id: 21_064}] =
                 Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
      end
    end
  end

  defp mark_of_kazzak(player) do
    mark =
      Semantics.compile(%Spell{
        id: 21_056,
        school: :shadow,
        duration_ms: 60_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_mana_leech,
            base_points: 250,
            misc_value: 0,
            amplitude_ms: 1_000,
            implicit_target_a: :target_enemy
          }
        ]
      })

    {marked, _events} = Aura.apply_spell(player, %CastContext{caster_guid: @kazzak, caster_level: 63}, mark, 1_000)
    marked
  end

  defp player(_context) do
    %{
      player: %Character{
        object: %Object{guid: Unique.integer()},
        unit: %Unit{
          health: 3_000,
          max_health: 3_000,
          level: 60,
          power_type: 0,
          power1: 150,
          max_power1: 5_000,
          auras: []
        },
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
