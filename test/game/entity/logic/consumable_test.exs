defmodule ThistleTea.Game.Entity.Logic.ConsumableTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "receive/4" do
    test "Noggenfogger requests exactly one self cast with 20/20/60 weights", %{character: character} do
      spell = consumable(16_589, "spell_noggenfogger_elixir")
      context = %{CastContext.from_caster(character, spell, 1) | cast_item_guid: 1234}
      {unchanged, [%RandomChoice{} = choice]} = SpellEffect.receive(character, context, spell, 0)
      assert unchanged.unit == character.unit
      assert RandomChoice.total_weight(choice) == 10

      for {roll, id} <- [{1, 16_595}, {2, 16_595}, {3, 16_593}, {4, 16_593}, {5, 16_591}, {10, 16_591}] do
        assert [%Effects.TriggerSpell{spell_id: ^id, source_guid: 1, target_guid: 1, cast_item_guid: nil}] =
                 RandomChoice.select(choice, roll)
      end
    end

    test "Deviate Fish includes all six equally likely outcomes", %{character: character} do
      choice = choice(character, consumable(8063, "spell_deviate_fish"))
      assert RandomChoice.total_weight(choice) == 6

      assert Enum.map(1..6, fn roll -> hd(RandomChoice.select(choice, roll)).spell_id end) ==
               [8064, 8065, 8066, 8067, 8068, 8070]
    end

    test "Savory Deviate Delight chooses only the two supported build costumes for each gender", %{character: c} do
      for {gender, expected} <- [{0, [8219, 8221]}, {1, [8220, 8222]}] do
        character = %{c | unit: %{c.unit | gender: gender}}
        choice = choice(character, consumable(8213, "spell_cooked_deviate_fish"))
        assert RandomChoice.total_weight(choice) == 2
        assert Enum.map(1..2, fn roll -> hd(RandomChoice.select(choice, roll)).spell_id end) == expected
      end
    end

    test "only the player's first self-targeted dummy effect requests an outcome", %{character: c} do
      for {id, script} <- [
            {8063, "spell_deviate_fish"},
            {8213, "spell_cooked_deviate_fish"},
            {16_589, "spell_noggenfogger_elixir"}
          ] do
        spell = consumable(id, script)
        context = CastContext.from_caster(c, spell, 1)
        mob = %Mob{object: c.object, unit: c.unit, internal: c.internal, movement_block: c.movement_block}
        assert {_, []} = SpellEffect.receive(mob, context, spell, 0)
        assert {_, []} = SpellEffect.receive(c, %{context | caster_guid: 2}, spell, 0)
        second_effect = %{spell | effects: [%{hd(spell.effects) | index: 1}]}
        assert {_, []} = SpellEffect.receive(c, context, second_effect, 0)
      end
    end
  end

  describe "resolve/2" do
    test "one selected alternative fully resolves its nested triggers and retains effect order", %{character: c} do
      spell = %Spell{
        id: 90_999_876,
        effects: [%Effect{index: 0, type: :heal, base_points: 10, implicit_target_a: :caster}]
      }

      character = %{c | internal: %{c.internal | spellbook: %{spell.id => spell}}}
      animation = %Effects.EmoteAnimation{emote_id: 4}
      trigger = Effects.trigger_spell(1, 60, 1, spell.id)
      choice = %RandomChoice{choices: [{2, [animation, trigger]}, {3, [animation, trigger]}]}
      [^animation | resolved] = EffectResolver.resolve(character, choice)
      assert Enum.count(resolved, &is_struct(&1, Effects.SpellGo)) == 1

      assert [%Effects.DeliverSpell{target_guid: 1, spell: ^spell}] =
               Enum.filter(resolved, &is_struct(&1, Effects.DeliverSpell))

      refute Enum.any?(resolved, &is_struct(&1, Effects.TriggerSpell))
      assert EffectResolver.resolve(character, %RandomChoice{choices: []}) == []
      assert EffectResolver.resolve(character, %RandomChoice{choices: [{1, []}]}) == []
    end
  end

  describe "tick/2" do
    test "Party Time starts after ten seconds and schedules one animation per tick", %{character: c} do
      {partying, _} = Aura.apply_spell(c, 1, 60, party_time(), 1_000)
      assert Aura.next_event_at(partying) == 11_000
      assert {^partying, []} = Aura.tick(partying, 10_999)
      {ticked, [%RandomChoice{} = choice]} = Aura.tick(partying, 11_000)
      assert animation_ids(choice) == [21, 4, 19, 11, 94]
      assert Aura.next_event_at(ticked) == 21_000
      assert {^ticked, []} = Aura.tick(ticked, 11_000)
      {late, [%RandomChoice{}]} = Aura.tick(ticked, 36_000)
      assert Aura.next_event_at(late) == 41_000
    end

    test "movement excludes dancing without mutating movement or a persistent pose", %{character: c} do
      for flags <- [1, 2, 4, 8, 0x40, 0x80, 0x2000, 0x4000, 0x04000000] do
        moving = %{c | movement_block: %{c.movement_block | movement_flags: flags}}
        {partying, _} = Aura.apply_spell(moving, 1, 60, party_time(), 0)
        {ticked, [%RandomChoice{} = choice]} = Aura.tick(partying, 10_000)
        assert animation_ids(choice) == [21, 4, 19, 11]
        assert ticked.movement_block == moving.movement_block
        assert ticked.unit.npc_emote_state == moving.unit.npc_emote_state
      end
    end

    test "cancel, expiry and death stop periodic animations", %{character: c} do
      {partying, _} = Aura.apply_spell(c, 1, 60, party_time(), 0)
      {cancelled, _} = Aura.cancel_spell(partying, 8067, 9_000)
      assert cancelled.unit.auras == []
      assert {^cancelled, []} = Aura.tick(cancelled, 10_000)
      {expired, _} = Aura.tick(partying, 120_000)
      assert expired.unit.auras == []
      assert {^expired, []} = Aura.tick(expired, 130_000)
      dead = Core.take_damage(partying, 100, 9_000)
      assert dead.unit.auras == []
      assert {^dead, []} = Aura.tick(dead, 10_000)
    end
  end

  defp choice(character, spell) do
    {_, [%RandomChoice{} = choice]} =
      SpellEffect.receive(character, CastContext.from_caster(character, spell, 1), spell, 0)

    choice
  end

  defp animation_ids(choice) do
    for roll <- 1..RandomChoice.total_weight(choice), do: hd(RandomChoice.select(choice, roll)).emote_id
  end

  defp consumable(id, script) do
    %Spell{id: id, script_name: script, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :caster}]}
  end

  defp party_time do
    %Spell{
      id: 8067,
      duration_ms: 120_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :periodic_emote, amplitude_ms: 10_000, implicit_target_a: :caster}
      ]
    }
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{gender: 0, level: 60, health: 100, max_health: 100, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }
    }
  end
end
