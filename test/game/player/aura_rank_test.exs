defmodule ThistleTea.Game.Player.AuraRankTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpellRequirements
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "cast_result/3" do
    test "uses an unlearned lower rank and reports the requested spell", ctx do
      assert {:ok, state} = Spellcasting.cast_result(ctx.state, ctx.high.id, ctx.wire)
      assert state.character.internal.casting.spell == ctx.low
      assert state.character.internal.casting.requested_spell == ctx.high
      assert Map.keys(state.character.internal.spellbook) == [ctx.high.id]
      {character, events} = finish(state.character, ctx.targets)
      assert character.unit.power1 == 90
      assert Enum.any?(events, &match?(%Effects.SpellGo{spell_id: id} when id == ctx.low.id, &1))
      assert Enum.any?(events, &match?(%Effects.DeliverSpell{spell: spell} when spell == ctx.low, &1))
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: requested, result: 0}}}
      assert requested == ctx.high.id
    end

    test "rejects a target below the first rank without spending mana", ctx do
      spell = %{ctx.high | previous_in_chain: nil}
      assert {:error, state} = Spellcasting.cast_result(ctx.state, spell, ctx.wire)
      assert state.character.internal.casting == nil
      assert state.character.unit.power1 == 100
      assert state.character.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: requested, reason: 0x2B}}}
      assert requested == spell.id
    end

    test "cancellation and resource errors identify the requested rank", ctx do
      assert {:ok, state} = Spellcasting.cast_result(ctx.state, ctx.high, ctx.wire)
      state = Spellcasting.cancel(state)
      assert state.character.internal.casting == nil
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: requested, reason: 0x23}}}
      assert requested == ctx.high.id
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{spell: selected}}}
      assert selected == ctx.low.id

      state = %{ctx.state | character: %{ctx.state.character | unit: %{ctx.state.character.unit | power1: 0}}}
      assert {:error, _state} = Spellcasting.cast_result(state, ctx.high, ctx.wire)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: ^requested, reason: 0x4D}}}
    end

    test "rechecks the selected rank at launch", ctx do
      Metadata.update(ctx.target, %{level: 50})
      assert {:ok, state} = Spellcasting.cast_result(ctx.state, ctx.high, ctx.wire)
      Metadata.update(ctx.target, %{level: 1})
      {character, _events} = finish(state.character, ctx.targets)
      assert character.internal.casting == nil
      assert character.unit.power1 == 100
      assert character.internal.cooldowns == %{}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x2B}}}
    end

    test "self casts select a rank from the owner's level", ctx do
      state = %{ctx.state | character: %{ctx.state.character | unit: %{ctx.state.character.unit | level: 1}}}
      assert {:ok, state} = Spellcasting.cast_result(state, ctx.high, <<0::16>>)
      assert state.character.internal.casting.spell.id == ctx.low.id
      {character, _events} = finish(state.character, Target.self(state.guid))
      assert character.unit.stamina == 13
      assert hd(character.unit.auras).spell.id == ctx.low.id
    end
  end

  describe "aura_rank/2" do
    test "stops at missing or cyclic ancestors", ctx do
      :ets.insert(SpellLoader, {{:spell, ctx.low.id}, nil})
      assert SpellLoader.aura_rank(ctx.high, 1) == nil
      :ets.insert(SpellLoader, {{:spell, ctx.low.id}, %{ctx.low | spell_level: 40, previous_in_chain: ctx.high.id}})
      :ets.insert(SpellLoader, {{:spell, ctx.high.id}, ctx.high})
      assert SpellLoader.aura_rank(ctx.high, 1) == nil
    end
  end

  defp finish(character, targets) do
    cast = character.internal.casting
    now = cast.started_at + 2_000
    character = Casting.complete(character, now)

    character =
      case Enum.find(character.internal.events, &match?(%Effects.CheckCastRequirements{}, &1)) do
        %Effects.CheckCastRequirements{cast: waiting} ->
          requirements = SpellRequirements.resolve(character, waiting.spell, targets)
          character = %{character | internal: %{character.internal | events: []}}
          Casting.resolve_requirements(character, waiting, requirements, now)

        nil ->
          character
      end

    {EventSink.emit_pending(character, Context.new(self())), character.internal.events}
  end

  defp caster(_context) do
    [guid, target, low_id, high_id] = for _ <- 1..4, do: System.unique_integer([:positive]) + 95_000_000
    world = WorldRef.instance(999, guid)
    faction = %FactionTemplate{id: 1, faction_group: 1, friend_group: 1, enemy_group: 2}
    Metadata.put(target, %{level: 1, alive?: true, faction_template: faction})
    Metadata.put(guid, %{level: 60, alive?: true, faction_template: faction})
    SpatialHash.update(:players, target, world, 1.0, 0.0, 0.0)

    low = %Spell{
      id: low_id,
      name: "Ranked Buff",
      rank: 1,
      first_in_chain: low_id,
      spell_level: 1,
      cast_time_ms: 1_000,
      duration_ms: 60_000,
      mana_cost: 10,
      power_type: 0,
      range_yards: 30.0,
      attributes: MapSet.new([:ignore_line_of_sight]),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :mod_stat,
          misc_value: 2,
          base_points: 3,
          implicit_target_a: :target_ally
        }
      ]
    }

    high = %{low | id: high_id, rank: 2, previous_in_chain: low_id, spell_level: 60, mana_cost: 80}
    :ets.insert(SpellLoader, {{:spell, low_id}, low})

    on_exit(fn ->
      Metadata.delete(target)
      Metadata.delete(guid)
      SpatialHash.remove(:players, target)
      Enum.each([low_id, high_id], &:ets.delete(SpellLoader, {:spell, &1}))
    end)

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{
        level: 60,
        health: 100,
        max_health: 100,
        power1: 100,
        max_power1: 100,
        power_type: 0,
        base_stamina: 10
      },
      player: %Player{},
      internal: %Internal{world: world, spellbook: %{high_id => high}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    targets = Target.unit(target)

    %{
      state: %State{guid: guid, character: character},
      target: target,
      targets: targets,
      wire: TargetCodec.encode(targets),
      low: low,
      high: high
    }
  end
end
