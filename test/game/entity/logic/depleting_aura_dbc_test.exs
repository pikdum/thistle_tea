defmodule ThistleTea.Game.Entity.Logic.DepletingAuraDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db
  @spell_ids [24_661, 24_662, 24_574, 24_575, 24_590, 29_284, 26_463, 26_464, 26_465, 29_286]

  setup [:character]

  describe "receive/4" do
    test "Brittle Armor follows the real dummy and removal spells on its owner", %{character: character} do
      buffed = cast(character, 24_574, 0)
      assert holder(buffed, 24_575).stacks == 10
      assert buffed.unit.normal_resistance == 2_100
      assert Skills.defense_value(buffed) == 330

      {spent, events} =
        Aura.reactions(buffed, :hit_taken, %{
          attacker_guid: 2,
          proc_type: :take_melee_swing,
          outcome: :normal,
          damage: 50,
          now: 1_000
        })

      assert [%Effects.TriggerSpell{spell_id: 24_590}] = events
      spent = deliver(spent, events, 1_000)
      assert holder(spent, 24_575).stacks == 9
      assert spent.unit.normal_resistance == 1_900
      assert Skills.defense_value(spent) == 327
    end

    test "Mercurial Shield initializes ten resistance stacks and consumes one on a spell hit", %{character: character} do
      buffed = cast(character, 26_463, 0)
      assert holder(buffed, 26_464).stacks == 10
      assert holder(buffed, 26_464).expires_at == 60_000
      assert buffed.unit.fire_resistance == 100

      {spent, events} =
        Aura.reactions(buffed, :spell_hit_taken, %{
          attacker_guid: 2,
          spell: SpellLoader.load(133),
          proc_type: :take_harmful_spell,
          outcome: :normal,
          damage: 50,
          now: 1_000
        })

      assert [%Effects.TriggerSpell{spell_id: 26_465}] = events
      spent = deliver(spent, events, 1_000)
      assert spent.unit.fire_resistance == 90
      assert spent.unit.holy_resistance == 0
    end

    test "Restless Strength responds to real Auto Shot and Arcane Shot feedback", %{character: character} do
      buffed = cast(character, 24_661, 0)
      assert holder(buffed, 24_662).stacks == 20
      assert WeaponDamage.flat_bonus(buffed, :physical, nil) == 40

      for {id, type} <- [{75, :deal_ranged_attack}, {3044, :deal_ranged_ability}] do
        spent =
          SpellFeedback.receive(
            buffed,
            %{victim_guid: 2, outcome: :normal, proc_type: type},
            SpellLoader.load(id),
            1_000
          )

        assert holder(spent, 24_662).stacks == 19
        assert WeaponDamage.flat_bonus(spent, :physical, nil) == 38
      end
    end
  end

  defp cast(character, id, now) do
    spell = Map.fetch!(character.internal.spellbook, id)
    context = CastContext.from_caster(character, spell, 1)
    {character, events} = SpellEffect.receive(character, context, spell, now)
    deliver(character, events, now)
  end

  defp deliver(character, events, now) do
    Enum.reduce(events, character, fn
      %Effects.TriggerSpell{} = trigger, current ->
        deliver(current, Spells.resolve(current, trigger), now)

      %Effects.DeliverSpell{target_guid: 1, cast_context: context, spell: spell}, current ->
        {current, events} = SpellEffect.receive(current, context, spell, now)
        deliver(current, events, now)

      %Effects.DeliverSpell{target_guid: target}, _current ->
        flunk("trigger delivered to #{target}")

      _event, current ->
        current
    end)
  end

  defp holder(character, id), do: Enum.find(character.unit.auras, &(&1.spell.id == id))

  defp character(_context) do
    spells = Map.new(@spell_ids, &{&1, SpellLoader.load(&1)})

    spells =
      Enum.reduce([{29_284, "spell_brittle_armor_dummy"}, {29_286, "spell_mercurial_shield_dummy"}], spells, fn {id,
                                                                                                                 name},
                                                                                                                book ->
        Map.update!(book, id, &Semantics.compile(%{&1 | script_name: name, semantics: nil}))
      end)

    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{spellbook: spells},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          class: 8,
          auras: [],
          normal_resistance: 100,
          base_normal_resistance: 100,
          base_holy_resistance: 0,
          base_fire_resistance: 0,
          base_nature_resistance: 0,
          base_frost_resistance: 0,
          base_shadow_resistance: 0,
          base_arcane_resistance: 0
        }
      }
    }
  end
end
