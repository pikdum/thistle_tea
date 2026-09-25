defmodule ThistleTea.Game.Entity.Logic.Aura.FormLinksDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db
  @forms [{768, :strength, 24_900}, {5487, :stamina, 24_899}, {9634, :stamina, 24_899}]

  setup [:character]

  describe "apply_spell/5" do
    test "all Heart of the Wild ranks apply their exact form-dependent percentage", %{character: character} do
      for {id, amount} <- [{17_003, 4}, {17_004, 8}, {17_005, 12}, {17_006, 16}, {24_894, 20}] do
        spell = SpellLoader.load(id)
        assert Enum.map(spell.form_auras, & &1.id) == [24_899, 24_900]
        assert Enum.all?(spell.form_auras, &(&1.form_auras == []))
        {learned, _} = cast(character, spell, 1000)
        assert learned.unit.intellect == 100 + amount

        for {form_id, stat, boost_id} <- @forms do
          {shifted, _} = cast(learned, SpellLoader.load(form_id), 2000)
          assert Map.fetch!(shifted.unit, stat) == 100 + amount
          assert Aura.has_spell?(shifted, boost_id)
          assert_in_delta shifted.unit.health / shifted.unit.max_health, 0.5, 0.001
          {normal, _} = Aura.cancel_spell(shifted, form_id, 3000)
          assert normal.unit.stamina == 100
          assert normal.unit.strength == 100
          assert normal.unit.intellect == 100 + amount
          refute Aura.has_spell?(normal, boost_id)
        end
      end
    end

    test "learning Leader of the Pack in form creates the visible party source immediately", %{character: character} do
      {cat, _} = cast(character, SpellLoader.load(768), 1000)
      {leader, _} = cast(cat, SpellLoader.load(17_007), 2000)
      holder = Enum.find(leader.unit.auras, &(&1.spell.id == 24_932))
      assert is_integer(holder.slot)
      refute Spell.attribute?(holder.spell, :passive)
      assert holder.area_radius == 45.0
      assert Aura.flat_amount(leader, :mod_crit_percent) == 3
      {leader, events} = Aura.tick(leader, 2000)
      assert [%Effects.DeliverSpellToQuery{query: {:party_aoe, 45.0}, spell: %{id: 24_932}}] = events
      {moonkin, _} = cast(leader, SpellLoader.load(24_858), 3000)
      refute Aura.has_spell?(moonkin, 24_932)
      assert Aura.has_spell?(moonkin, 17_007)
    end
  end

  defp character(_context) do
    unit =
      Stats.recompute(%Unit{
        race: 4,
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

  defp cast(character, spell, now), do: Aura.apply_spell(character, 1, 60, spell, now)
end
