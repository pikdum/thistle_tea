defmodule ThistleTea.Game.Entity.Logic.WeaponProcsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.WeaponProcs
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "spell_allowed?/1" do
    test "real melee abilities qualify while ordinary ranged spells do not" do
      for id <- [78, 1752, 6770, 2973], do: assert(WeaponProcs.spell_allowed?(SpellLoader.load(id)))
      for id <- [75, 19_434, 2764, 5019, 133], do: refute(WeaponProcs.spell_allowed?(SpellLoader.load(id)))
    end
  end

  describe "innate_events/6" do
    test "Destiny buffs its wielder through implicit targeting and expires without leaving strength" do
      spell = SpellLoader.load(17_152)
      assert spell.proc_chance == 101
      assert spell.duration_ms == 10_000

      character = %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{level: 60, health: 100, max_health: 100, base_strength: 20, strength: 20},
        internal: %Internal{spellbook: %{spell.id => spell}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      item = Item.build(%ItemTemplate{entry: 647, class: 2, delay: 2600, spellid_1: spell.id, spelltrigger_1: 2}, 99)
      hit = %Effects.TriggerWeaponProcs{source_guid: 1, target_guid: 2, hand: :mainhand}

      assert {[trigger], true} =
               WeaponProcs.innate_events(character, hit, item, %{spell.id => spell}, 1_000, fn -> 0.04 end)

      events = Spells.resolve(character, trigger)

      assert [%Effects.DeliverSpell{target_guid: 1, cast_context: context}] =
               Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

      assert context.cast_item_guid == 99
      assert context.triggered?
      {buffed, _events} = SpellEffect.receive(character, context, spell, 1_000)
      assert buffed.unit.strength == 220
      assert [%{spell: %{id: 17_152}, expires_at: 11_000}] = buffed.unit.auras
      {expired, _events} = Aura.expire_due(buffed, 11_000)
      assert expired.unit.strength == 20
      assert expired.unit.auras == []
    end
  end
end
