defmodule ThistleTea.Game.Entity.Logic.Aura.FormLinksTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "apply_spell/5" do
    test "Heart of the Wild follows the active form without compounding canonical stats", %{character: character} do
      {learned, _} = cast(character, heart(), 1000)
      assert learned.unit.intellect == 120
      assert learned.unit.strength == 100
      {cat, _} = cast(learned, form(1), 2000)
      assert cat.unit.strength == 120
      assert cat.unit.stamina == 100
      assert cat.unit.base_strength == 100
      assert Aura.has_spell?(cat, 24_900)
      {bear, _} = cast(cat, form(5), 3000)
      assert bear.unit.strength == 100
      assert bear.unit.stamina == 120
      assert bear.unit.health == 1210
      assert bear.unit.max_health == 2420
      refute Aura.has_spell?(bear, 24_900)
      assert Aura.has_spell?(bear, 24_899)
      assert {^bear, []} = Aura.tick(bear, 3500)

      {normal, _} = Aura.cancel_spell(bear, form(5).id, 4000)
      assert normal.unit.health == 910
      assert normal.unit.max_health == 1820
      assert normal.unit.intellect == 120
      refute Aura.has_spell?(normal, 24_899)
    end

    test "learning and replacing the parent in form replaces its child magnitude", %{character: character} do
      {bear, _} = cast(character, form(5), 1000)
      weak = %{heart() | id: 17_003, rank: 1, effects: [stat_effect(4, 3)]}
      {weak_bear, _} = cast(bear, weak, 2000)
      assert weak_bear.unit.stamina == 104
      {strong_bear, _} = cast(weak_bear, heart(), 3000)
      assert strong_bear.unit.stamina == 120
      assert [%Holder{auras: [%{amount: 20}]}] = Enum.filter(strong_bear.unit.auras, &(&1.spell.id == 24_899))
      refute Aura.has_spell?(strong_bear, weak.id)
      strong_bear = %{strong_bear | internal: %{strong_bear.internal | spellbook: %{heart().id => heart()}}}
      removed = SpellRemoval.remove(strong_bear, [heart().id], 4000)
      assert removed.unit.stamina == 100
      refute Aura.has_spell?(removed, 24_899)
    end

    test "party aura sources retain visibility, refresh recipients and never stack with another source", %{
      character: character
    } do
      {cat, _} = cast(character, form(1), 1000)
      {leader, _} = cast(cat, leader(), 2000)
      holder = Enum.find(leader.unit.auras, &(&1.spell.id == 24_932))
      assert is_integer(holder.slot)
      assert holder.area_radius == 45.0
      assert holder.next_area_refresh_at == 2000
      {leader, events} = Aura.tick(leader, 2000)
      assert [%{query: {:party_aoe, 45.0}, exclude_guids: [1], spell: delivered}] = events
      assert delivered.id == 24_932
      assert Aura.flat_amount(leader, :mod_crit_percent) == 3
      {leader, _} = Aura.apply_spell(leader, 2, 60, delivered, 2100)
      assert Aura.flat_amount(leader, :mod_crit_percent) == 3
      assert length(Enum.filter(leader.unit.auras, &(&1.spell.id == delivered.id))) == 1

      {recipient, _} = Aura.apply_spell(character, 2, 60, delivered, 2100)
      assert Aura.flat_amount(recipient, :mod_crit_percent) == 3
      {expired, _} = Aura.tick(recipient, 4600)
      refute Aura.has_spell?(expired, delivered.id)

      {normal, _} = Aura.cancel_spell(leader, form(1).id, 2200)
      refute Aura.has_spell?(normal, delivered.id)
      {_normal, events} = Aura.tick(normal, 3000)
      assert events == []
    end

    test "death removes form boosts while retaining the parent passive", %{character: character} do
      {active, _} = cast(character, heart(), 1000)
      {active, _} = cast(active, form(5), 2000)
      dead = Core.take_damage(active, 5000, 3000)
      assert dead.unit.health == 0
      assert Aura.has_spell?(dead, heart().id)
      refute Aura.has_spell?(dead, 24_899)
      {alive, _} = Death.resurrect(dead, 0.5, 4000)
      {bear, _} = cast(alive, form(5), 5000)
      assert bear.unit.stamina == 120
      assert_in_delta bear.unit.health / bear.unit.max_health, 0.5, 0.001
    end

    test "Bear to Dire Bear refreshes shared boosts without losing or duplicating them", %{character: character} do
      {active, _} = cast(character, heart(), 1000)
      {active, _} = cast(active, leader(), 1000)
      {bear, _} = cast(active, form(5), 2000)
      {dire, _} = cast(bear, form(8), 3000)
      assert Enum.count(dire.unit.auras, &(&1.spell.id == 24_899)) == 1
      assert Enum.count(dire.unit.auras, &(&1.spell.id == 24_932)) == 1
      assert dire.unit.stamina == 120
      assert Aura.flat_amount(dire, :mod_crit_percent) == 3
    end

    test "visible linked boosts obey buff capacity and cannot outlive an evicted parent", %{character: character} do
      full =
        Enum.reduce(1..31, character, fn id, current ->
          spell = %Spell{id: 5000 + id, effects: [%Effect{type: :apply_aura, aura: :dummy}]}
          current |> cast(spell, id) |> elem(0)
        end)

      {cat, _} = cast(full, form(1), 1000)
      {active, _} = cast(cat, leader(), 2000)
      assert Enum.count(active.unit.auras, &is_integer(&1.slot)) <= 32
      {removed, _} = Aura.remove_spells(active, [leader().id], 3000)
      refute Aura.has_spell?(removed, 24_932)
    end
  end

  defp character(_context) do
    unit =
      Stats.recompute(%Unit{
        class: 11,
        level: 60,
        base_strength: 100,
        base_agility: 100,
        base_stamina: 100,
        base_intellect: 100,
        base_spirit: 100,
        base_health: 1000,
        base_mana: 1000,
        health: 910,
        power1: 1000,
        auras: []
      })

    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: unit,
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp heart do
    %Spell{
      id: 24_894,
      spell_icon: 240,
      duration_ms: -1,
      first_in_chain: 17_003,
      rank: 5,
      attributes: MapSet.new([:passive]),
      effects: [stat_effect(20, 3)],
      form_auras: [
        %Spell{
          id: 24_899,
          duration_ms: -1,
          stances: 144,
          attributes: MapSet.new([:ability]),
          effects: [stat_effect(0, 2)]
        },
        %Spell{id: 24_900, duration_ms: -1, stances: 1, effects: [stat_effect(0, 0)]}
      ]
    }
  end

  defp leader do
    %Spell{
      id: 17_007,
      duration_ms: -1,
      attributes: MapSet.new([:passive]),
      effects: [%Effect{type: :apply_aura, aura: :dummy}],
      form_auras: [
        %Spell{
          id: 24_932,
          duration_ms: -1,
          stances: 145,
          effects: [%Effect{type: :apply_area_aura, aura: :mod_crit_percent, base_points: 3, radius_yards: 45.0}]
        }
      ]
    }
  end

  defp stat_effect(amount, stat),
    do: %Effect{type: :apply_aura, aura: :mod_total_stat_percent, base_points: amount, misc_value: stat}

  defp form(form) do
    health = if form in [5, 8], do: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 400}], else: []
    %Spell{id: 1000 + form, effects: [%Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: form} | health]}
  end

  defp cast(character, spell, now), do: Aura.apply_spell(character, 1, 60, spell, now)
end
