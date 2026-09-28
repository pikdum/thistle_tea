defmodule ThistleTea.Game.Spell.TransporterDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @spells [23_441, 23_442, 23_444, 23_445, 23_446, 23_448, 23_449, 23_453]

  setup [:seed_caches, :traveler]

  describe "receive/4" do
    test "Gadgetzan child spells preserve teleport requests and the arrival chain", %{traveler: traveler} do
      {_, [%RandomChoice{} = choice]} = cast(traveler, 23_453)
      [success] = RandomChoice.select(choice, 1)
      assert {_, [%Effects.TeleportToSpellTarget{spell_id: 23_441}]} = deliver(traveler, success)

      [failure] = RandomChoice.select(choice, 3)

      assert {_, [teleport, arrival]} = deliver(traveler, failure)
      assert %Effects.TeleportToSpellTarget{spell_id: 23_446} = teleport
      assert %Effects.TriggerSpell{spell_id: 23_448} = arrival

      assert {_, [%RandomChoice{}]} = deliver(traveler, arrival)
    end

    test "malfunction transforms and stuns for ten seconds, then restores appearance", %{traveler: traveler} do
      {_, [%RandomChoice{} = choice]} = cast(traveler, 23_448)
      [trigger] = RandomChoice.select(choice, 1)
      {changed, _} = deliver(traveler, trigger)
      assert changed.unit.display_id == 77
      assert Aura.has_aura?(changed, :mod_stun)
      assert Aura.has_spell?(changed, 23_444)
      {expired, _} = Aura.tick(changed, 11_001)
      assert expired.unit.display_id == traveler.unit.display_id
      refute Aura.has_aura?(expired, :mod_stun)
      refute Aura.has_spell?(expired, 23_444)
    end

    test "Everlook fire damages the traveler every two seconds and stops on death", %{traveler: traveler} do
      {_, [%Effects.TeleportToSpellTarget{}, %RandomChoice{} = choice]} = cast(traveler, 23_442)
      [trigger] = RandomChoice.select(choice, 12)
      {burning, _} = deliver(traveler, trigger)
      [holder] = burning.unit.auras
      assert holder.expires_at == 25_000
      assert Aura.next_event_at(burning) == 3_000

      {injured, events} = Aura.tick(burning, 3_000)
      assert injured.unit.health == 900
      assert Enum.any?(events, &match?(%Effects.SpellDamage{source_guid: 1, target_guid: 1, damage: 100}, &1))

      dead = Enum.reduce(2..10, injured, fn tick, entity -> elem(Aura.tick(entity, 1_000 + tick * 2_000), 0) end)
      assert dead.unit.health == 0
      refute Aura.has_spell?(dead, 23_449)
      {unchanged, events} = Aura.tick(dead, 23_000)
      assert unchanged.unit.health == 0
      refute Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
    end

    test "Evil Twin lasts two hours and can be removed through ordinary aura expiry", %{traveler: traveler} do
      {_, [%RandomChoice{} = choice]} = cast(traveler, 23_448)
      [trigger] = RandomChoice.select(choice, 2)
      {changed, _} = deliver(traveler, trigger)
      [holder] = changed.unit.auras
      assert holder.spell.id == 23_445
      assert holder.expires_at == 7_201_000
      {expired, _} = Aura.tick(changed, 7_201_001)
      refute Aura.has_spell?(expired, 23_445)
    end
  end

  defp cast(traveler, id) do
    spell = Map.fetch!(traveler.internal.spellbook, id)
    context = %{CastContext.from_caster(traveler, spell, 1) | cast_item_guid: 42}
    SpellEffect.receive(traveler, context, spell, 1_000)
  end

  defp deliver(traveler, trigger) do
    deliveries = Spells.resolve(traveler, trigger) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
    assert [%Effects.DeliverSpell{target_guid: 1, spell: spell, cast_context: context}] = deliveries
    SpellEffect.receive(traveler, context, spell, 1_000)
  end

  defp seed_caches(_context) do
    fixtures = [
      {CreatureTemplateLoader, 14_681, %CreatureTemplate{entry: 14_681, display_ids: [77]}},
      {SpellScriptName, 23_442, "spell_everlook_transporter"}
    ]

    for {table, key, value} <- fixtures do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    :ok
  end

  defp traveler(_context) do
    %{
      traveler: %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 1_000,
          max_health: 1_000,
          level: 60,
          display_id: 49,
          native_display_id: 49,
          auras: []
        },
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0), spellbook: Map.new(@spells, &{&1, SpellLoader.load(&1)})},
        movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
      }
    }
  end
end
