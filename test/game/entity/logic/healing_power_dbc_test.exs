defmodule ThistleTea.Game.Entity.Logic.HealingPowerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @bonuses [28_789, 28_823]
  @buffs [28_790, 28_791, 28_793, 28_795, 28_824, 28_825, 28_826, 28_827]

  setup [:catalog, :characters]

  describe "load/1" do
    test "six-piece bonuses retain their ten-percent direct-heal rules" do
      for {set_id, index, bonus, allowed, rejected} <- [
            {528, 1, 28_789, [635, 19_750], [331, 8013, 20_473]},
            {527, 0, 28_823, [331, 8004], [635, 19_750, 1064]}
          ] do
        set = DBC.get(ItemSet, set_id)
        assert Map.fetch!(set, :"set_spell_#{index}") == bonus
        assert Map.fetch!(set, :"set_threshold_#{index}") == 6
        spell = SpellLoader.cached(bonus)
        assert spell.proc_chance == 10
        assert spell.proc_charges == 0
        assert [%{aura: :dummy}] = spell.effects
        assert Proc.roll?(spell, nil, fn -> 0.1 end)
        refute Proc.roll?(spell, nil, fn -> 0.1001 end)

        for id <- allowed do
          heal = SpellLoader.load(id)
          assert Proc.eligible?(spell, heal, :deal_helpful_spell, :normal)
          assert Proc.eligible?(spell, heal, :deal_helpful_spell, :crit)
          refute Proc.eligible?(spell, heal, :deal_helpful_periodic, :normal)
          refute Proc.eligible?(spell, heal, :deal_helpful_spell, :cast_end)
        end

        for id <- rejected do
          refute Proc.eligible?(spell, SpellLoader.load(id), :deal_helpful_spell, :normal)
        end
      end
    end
  end

  describe "receive/4" do
    test "both sets deliver the class buff through resolved healing feedback", context do
      for {bonus, heal_id} <- [{28_789, 19_750}, {28_823, 331}], class <- [1, 2, 3, 8] do
        caster = equip(context.caster, bonus)
        recipient = recipient(context.recipient, class)
        {healed, buffed} = heal_and_proc(caster, recipient, SpellLoader.load(heal_id))
        assert healed.unit.health > recipient.unit.health
        assert length(buffed.unit.auras) == 1
        [holder] = buffed.unit.auras
        assert holder.caster_guid == caster.object.guid
        assert holder.item_source == nil
        assert holder.spell.duration_ms == 8_000
        assert_bonus(healed, buffed, class)

        {refreshed, _} = Aura.apply_spell(buffed, caster.object.guid, 60, holder.spell, 2_000)
        assert length(refreshed.unit.auras) == 1
        assert_bonus(healed, refreshed, class)
        {active, _} = Aura.tick(refreshed, 9_999)
        assert length(active.unit.auras) == 1
        {expired, _} = Aura.tick(active, 10_000)
        assert expired.unit.auras == []
        assert stats(expired) == stats(healed)
        dead = Core.take_damage(buffed, buffed.unit.health, 3_000)
        assert dead.unit.health == 0
        assert dead.unit.auras == []
        assert stats(dead) == stats(healed)
      end
    end

    test "set removal stops new procs without removing an already delivered buff", context do
      caster = equip(context.caster, 28_789)
      assert length(equip(caster, 28_789).unit.auras) == 1
      {_, buffed} = heal_and_proc(caster, recipient(context.recipient, 8), SpellLoader.load(19_750))
      removed = EquipmentAuras.sync(caster, [], &SpellLoader.cached/1, 2_000, [])
      assert removed.unit.auras == []
      {removed, _} = Effects.drain(removed)
      heal = SpellLoader.load(19_750)

      payload = %{
        victim_guid: buffed.object.guid,
        victim_class: 8,
        victim_alive?: true,
        proc_type: :deal_helpful_spell,
        outcome: :normal
      }

      assert SpellFeedback.receive(removed, payload, heal, 2_000).internal.events == []
      assert length(buffed.unit.auras) == 1
      assert length(equip(removed, 28_789).unit.auras) == 1
    end

    test "a recipient dying after feedback prevents delivery", context do
      caster = equip(context.caster, 28_789)

      payload = %{
        victim_guid: context.recipient.object.guid,
        victim_class: 8,
        victim_alive?: true,
        proc_type: :deal_helpful_spell,
        outcome: :normal
      }

      {caster, [event]} = caster |> SpellFeedback.receive(payload, SpellLoader.load(19_750), 1_000) |> Effects.drain()
      Metadata.put(context.recipient.object.guid, %{alive?: false, level: 60})
      assert Spells.resolve(caster, event) == []
    end
  end

  defp heal_and_proc(caster, recipient, heal) do
    cast = %{
      CastContext.from_caster(caster, heal, recipient.object.guid)
      | spell_crit_chance: 0,
        target_hostile?: false
    }

    {healed, events} = SpellEffect.receive(recipient, cast, heal, 1_000)
    EventSink.emit(healed, Enum.find(events, &is_struct(&1, Effects.SpellHeal)))
    assert_receive {:"$gen_cast", {:spell_outcome, payload}}
    assert payload.victim_class == recipient.unit.class
    {caster, [event]} = caster |> SpellFeedback.receive(payload, heal, 1_000) |> Effects.drain()
    assert event.target_guid == recipient.object.guid
    deliveries = caster |> Spells.resolve(event) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
    assert [delivery] = deliveries
    {buffed, _} = SpellEffect.receive(healed, delivery.cast_context, delivery.spell, 1_000)
    {healed, buffed}
  end

  defp assert_bonus(before, after_buff, 1),
    do: assert(after_buff.unit.normal_resistance == before.unit.normal_resistance + 700)

  defp assert_bonus(before, after_buff, 2) do
    assert Regen.tick(after_buff, 2_000).unit.power1 == Regen.tick(before, 2_000).unit.power1 + 11
  end

  defp assert_bonus(before, after_buff, 3), do: assert(after_buff.unit.attack_power == before.unit.attack_power + 140)

  defp assert_bonus(before, after_buff, 8) do
    assert stats(after_buff).spell_damage == stats(before).spell_damage + 80
  end

  defp stats(character) do
    cast = CastContext.from_caster(character, %Spell{id: 133, school: :fire}, character.object.guid)

    %{
      armor: character.unit.normal_resistance,
      attack: character.unit.attack_power,
      spell_damage: cast.spell_damage_bonus.fire
    }
  end

  defp equip(caster, id) do
    get_spell = fn spell_id -> %{SpellLoader.cached(spell_id) | proc_chance: 100} end
    set_id = if id == 28_789, do: 528, else: 527
    {caster, _} = caster |> EquipmentAuras.sync([], get_spell, 0, [{:item_set, set_id, id}]) |> Effects.drain()
    caster
  end

  defp recipient(character, class) do
    %{character | unit: Stats.recompute(%{character.unit | class: class})}
  end

  defp catalog(_context) do
    for id <- @bonuses ++ @buffs do
      cache_fixture(SpellChain, {:chain, id}, nil)
      spell = SpellLoader.load(id)

      rule =
        case id do
          28_789 -> %ProcRule{spell_family: 10, family_mask_0: 0xC0006000}
          28_823 -> %ProcRule{family_mask_0: 0xC0}
          _ -> spell.proc_rule
        end

      cache_fixture(SpellLoader, {:spell, id}, %{spell | proc_rule: rule})
    end

    :ok
  end

  defp cache_fixture(table, key, value) do
    previous = :ets.lookup(table, key)
    :ets.insert(table, {key, value})

    on_exit(fn ->
      :ets.delete(table, key)
      :ets.insert(table, previous)
    end)
  end

  defp characters(_context) do
    guid = System.unique_integer([:positive]) + 51_000_000

    caster = %Character{
      object: %Object{guid: guid},
      unit: %Unit{
        class: 2,
        level: 60,
        health: 500,
        max_health: 1_000,
        power_type: 0,
        power1: 0,
        max_power1: 1_000,
        spirit: 0,
        base_attack_power: 100,
        base_normal_resistance: 100,
        auras: []
      },
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0), last_mana_use_at: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    recipient = %{caster | object: %Object{guid: guid + 1}}
    Metadata.put(recipient.object.guid, %{alive?: true, level: 60})
    on_exit(fn -> Metadata.delete(recipient.object.guid) end)
    {:ok, _} = Entity.register(guid)
    %{caster: caster, recipient: recipient}
  end
end
