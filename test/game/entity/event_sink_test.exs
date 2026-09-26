defmodule ThistleTea.Game.Entity.EventSinkTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  defmodule UnsupportedEffect do
    @moduledoc false
    @enforce_keys [:value]
    defstruct [:value]
  end

  describe "emit/2" do
    test "cast completion reaches only the explicit caster owner with its proc origin" do
      guid = unique_guid()
      caster = %Character{object: %Object{guid: guid}}
      spell = %Spell{id: 7_268, dmg_class: 1, effects: [%Effect{type: :school_damage}]}
      effect = %Effects.SpellCastCompleted{source_guid: guid, target_guid: 99, spell: spell, proc_origin: :aura_or_item}
      EventSink.emit(caster, effect)
      refute_received {:"$gen_cast", {:spell_outcome, _}}
      EventSink.emit(caster, effect, Context.new(self()))

      assert_received {:"$gen_cast",
                       {:spell_outcome,
                        %{
                          spell: ^spell,
                          victim_guid: 99,
                          outcome: :cast_end,
                          proc_type: :deal_harmful_spell,
                          proc_origin: :aura_or_item
                        }}}
    end

    test "preserves spell requirements through queued cast failures" do
      character = %Character{
        object: %Object{guid: unique_guid()},
        internal: %Internal{world: WorldRef.instance(30, 1)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      spell = %Spell{
        id: 23_693,
        area_rules: [%Area{area_id: 2597}],
        required_focus_id: 3,
        equipped_item_class: 2,
        equipped_item_subclass_mask: 16
      }

      for reason <- [:requires_area, :requires_spell_focus, :equipped_item_class] do
        EventSink.emit(character, Effects.spell_cast_failed(spell, reason), Context.new(self()))
        assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{} = result}}
        assert result == Message.SmsgCastResult.failure(spell, reason)
        assert is_binary(Message.SmsgCastResult.to_binary(result))
      end
    end

    test "routes combo point awards to their caster and uses the explicit local owner" do
      caster_guid = unique_guid()
      award = %Effects.AddComboPoints{source_guid: caster_guid, target_guid: 99, amount: 2}
      caster = %Character{object: %Object{guid: caster_guid}}
      EventSink.emit(caster, award)
      refute_received {:"$gen_cast", {:add_combo_points, _award}}
      EventSink.emit(caster, award, Context.new(self()))
      assert_received {:"$gen_cast", {:add_combo_points, ^award}}
      Entity.register(caster_guid)
      on_exit(fn -> Entity.unregister(caster_guid) end)
      EventSink.emit(%Mob{object: %Object{guid: 99}}, award)
      assert_received {:"$gen_cast", {:add_combo_points, ^award}}
    end

    test "delivers a taxi spell through the explicit player owner context" do
      guid = unique_guid()
      character = %Character{object: %Object{guid: guid}}
      effect = %Effects.SendTaxiPath{target_guid: guid, path_id: 315, spell_id: 27_998}
      EventSink.emit(character, effect)
      refute_received ^effect
      EventSink.emit(character, effect, Context.new(self()))
      assert_received ^effect
    end

    test "environmental damage reaches the victim and nearby observers in the same world" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())
      other_world_guid = Guid.from_low_guid(:player, unique_guid())

      for {guid, map} <- [{owner_guid, 0}, {observer_guid, 0}, {other_world_guid, 1}] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, map, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid, other_world_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      for {type, type_id} <- [exhaustion: 0, drowning: 1, fall: 2, lava: 3, slime: 4, fire: 5] do
        for damage <- [0, 20] do
          effect = %Effects.EnvironmentalDamage{type: type, damage: damage, absorbed: 30, resisted: 150}
          EventSink.emit(character, effect)

          packet = %Message.SmsgEnvironmentalDamageLog{
            guid: owner_guid,
            damage_type: type_id,
            damage: damage,
            absorb: 30,
            resist: 150
          }

          assert_receive {:"$gen_cast", {:send_packet, ^packet}}
          assert_receive {:"$gen_cast", {:send_packet, ^packet, _opts}}
          refute_received {:"$gen_cast", {:send_packet, ^packet}}
          refute_received {:"$gen_cast", {:send_packet, ^packet, _opts}}
        end
      end
    end

    test "a selected periodic animation reaches the owner and same-world observers once" do
      [owner, observer, other_world] = Enum.map(1..3, fn _ -> Guid.from_low_guid(:player, unique_guid()) end)

      for {guid, map} <- [{owner, 0}, {observer, 0}, {other_world, 1}] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, map, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner, observer, other_world] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      choice = %Effects.RandomChoice{choices: [{1, [%Effects.EmoteAnimation{emote_id: 94}]}]}

      character = %Character{
        object: %Object{guid: owner},
        internal: %Internal{world: WorldRef.open(0), events: [choice]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert EventSink.emit_pending(character, Context.new(self())).internal.events == []
      packet = %Message.SmsgEmote{emote: 94, guid: owner}
      assert_receive {:"$gen_cast", {:send_packet, ^packet}}
      assert_receive {:"$gen_cast", {:send_packet, ^packet, _opts}}
      refute_receive {:"$gen_cast", {:send_packet, ^packet}}
      refute_receive {:"$gen_cast", {:send_packet, ^packet, _opts}}
    end

    test "delivers item transformation only to the explicit player owner" do
      character = %Character{object: %Object{guid: unique_guid()}}
      spell = %Spell{id: 21_180}
      effect = %Effects.TransformItem{cast_item_guid: 42, spell: spell, item_id: 17_223}
      EventSink.emit(character, effect)
      refute_received {:transform_item, _, _, _}
      EventSink.emit(character, effect, Context.new(self()))
      assert_received {:transform_item, 42, ^spell, 17_223}
      EventSink.emit(%Mob{}, effect, Context.new(self()))
      refute_received {:transform_item, _, _, _}
    end

    test "delivers scripted casts only through the explicit player owner context" do
      character = %Character{object: %Object{guid: unique_guid()}}
      entry = %CreatureSpell{spell_id: 15_065}
      effect = Effects.scripted_cast(entry, character.object.guid)
      EventSink.emit(character, effect)
      refute_received {:scripted_cast, _, _}
      EventSink.emit(character, effect, Context.new(self()))
      guid = character.object.guid
      assert_received {:scripted_cast, ^entry, ^guid}
    end

    setup [:metadata_fixtures]

    test "proc damage resolves from the aura carrier and reaches only a live target" do
      carrier_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)
      Metadata.put(target_guid, %{alive?: true, level: 60})

      on_exit(fn ->
        Entity.unregister(target_guid)
        Metadata.delete(target_guid)
      end)

      carrier = %Character{
        object: %Object{guid: carrier_guid},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      spell = %Spell{
        id: 90_030,
        school: :fire,
        effects: [%Effect{index: 1, type: :apply_aura, aura: :proc_trigger_damage, base_points: 10}]
      }

      request = Effects.proc_damage(target_guid, spell, 1)
      EventSink.emit(carrier, request)

      assert_receive {:"$gen_cast",
                      {:receive_spell, %CastContext{caster_guid: ^carrier_guid, caster_level: 60, proc_damage?: true},
                       %Spell{effects: [%Effect{type: :school_damage, index: 1}]}}}

      Metadata.update(target_guid, %{alive?: false})
      EventSink.emit(carrier, request)
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
      Metadata.delete(target_guid)
      EventSink.emit(carrier, request)
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end

    test "spell feedback retains the resolved spell and emitting target's life, resource and class" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(caster_guid)
      on_exit(fn -> Entity.unregister(caster_guid) end)

      target = %Mob{
        object: %Object{guid: target_guid},
        unit: %Unit{health: 25, power_type: 3, class: 11},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      spell = %Spell{id: 774, school: :nature}
      heal = Effects.spell_heal(caster_guid, target_guid, spell, 25, false, proc_origin: :suppressed)
      EventSink.emit(target, heal)

      assert_receive {:"$gen_cast",
                      {:spell_outcome,
                       %{
                         spell: ^spell,
                         victim_alive?: true,
                         victim_power_type: 3,
                         victim_class: 11,
                         proc_origin: :suppressed
                       }}}

      dead = %{target | unit: %{target.unit | health: 0, power_type: 1}}

      damage =
        Effects.spell_damage(caster_guid, target_guid, %Spell{id: 172, school: :shadow}, 25, proc_origin: :aura_or_item)

      EventSink.emit(dead, damage)

      assert_receive {:"$gen_cast",
                      {:spell_outcome, %{victim_alive?: false, victim_power_type: 1, proc_origin: :aura_or_item}}}

      EventSink.emit(%{target | object: %Object{guid: caster_guid}}, heal)
      assert_receive {:"$gen_cast", {:spell_outcome, payload}}
      refute Map.has_key?(payload, :victim_alive?)
      refute Map.has_key?(payload, :victim_power_type)
      refute Map.has_key?(payload, :victim_class)
    end

    test "direct healing reaches the recipient and observers without duplicating periodic logs" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())

      for guid <- [owner_guid, observer_guid] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, 0, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      spell = %Spell{id: 2050, school: :holy}
      EventSink.emit(character, Effects.spell_heal(observer_guid, owner_guid, spell, 25, true))

      expected = %Message.SmsgSpellheallog{
        target: owner_guid,
        caster: observer_guid,
        spell_id: 2050,
        amount: 25,
        critical?: true
      }

      assert_receive {:"$gen_cast", {:send_packet, ^expected, _opts}}
      assert_receive {:"$gen_cast", {:send_packet, ^expected}}

      EventSink.emit(character, Effects.spell_heal(observer_guid, owner_guid, spell, 25, false, periodic?: true))
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellheallog{}, _opts}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellheallog{}}}
    end

    test "spell damage reports health damage after absorption to both clients" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())

      for guid <- [owner_guid, observer_guid] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, 0, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      for periodic? <- [false, true], absorbed <- [0, 454, 500], proc_type <- [:deal_harmful_spell, nil] do
        spell = %Spell{id: 24_619, school: :shadow}

        effect =
          Effects.spell_damage(observer_guid, owner_guid, spell, 500,
            absorbed: absorbed,
            periodic?: periodic?,
            proc_type: proc_type
          )

        EventSink.emit(character, effect)
        damage = 500 - absorbed

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.SmsgSpellNonMeleeDamageLog{
                           damage: ^damage,
                           absorbed: ^absorbed,
                           periodic?: ^periodic?
                         }, _opts}}

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.SmsgSpellNonMeleeDamageLog{
                           damage: ^damage,
                           absorbed: ^absorbed,
                           periodic?: ^periodic?
                         }}}

        if proc_type do
          assert_receive {:"$gen_cast", {:spell_outcome, %{proc_type: ^proc_type}}}
        else
          refute_received {:"$gen_cast", {:spell_outcome, _}}
        end
      end
    end

    test "dispel feedback reaches the target and nearby observers" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())

      for guid <- [owner_guid, observer_guid] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, 0, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      EventSink.emit(character, %Effects.SpellDispel{
        source_guid: observer_guid,
        target_guid: owner_guid,
        spell_ids: [123, 456]
      })

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgSpelldispellog{caster: ^observer_guid, victim: ^owner_guid, spells: [123, 456]},
                       _opts}}

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgSpelldispellog{caster: ^observer_guid, victim: ^owner_guid, spells: [123, 456]}}}

      EventSink.emit(character, %Effects.DispelFailed{
        source_guid: observer_guid,
        target_guid: owner_guid,
        spell_ids: [789, 789]
      })

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgDispelFailed{caster: ^observer_guid, target: ^owner_guid, spells: [789, 789]},
                       _opts}}

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgDispelFailed{caster: ^observer_guid, target: ^owner_guid, spells: [789, 789]}}}
    end

    test "damage immunity reaches the owner and nearby observers" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())

      for guid <- [owner_guid, observer_guid] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, 0, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      effect = %Effects.SpellDamageImmune{source_guid: observer_guid, target_guid: owner_guid, spell_id: 772}
      EventSink.emit(character, effect)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgSpellordamageImmune{caster: ^observer_guid, target: ^owner_guid, spell_id: 772},
                       _opts}}

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgSpellordamageImmune{caster: ^observer_guid, target: ^owner_guid, spell_id: 772}}}
    end

    test "movement speeds reach nearby observers without duplicating the owner's update" do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      observer_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(owner_guid)
      Entity.register(observer_guid)
      SpatialHash.update(:players, owner_guid, 0, 0.0, 0.0, 0.0)
      SpatialHash.update(:players, observer_guid, 0, 1.0, 0.0, 0.0)

      on_exit(fn ->
        for guid <- [owner_guid, observer_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      character = %Character{
        object: %Object{guid: owner_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      EventSink.emit(character, Effects.movement_speed_changed(9.444444, :swim_speed), Context.new(self()))

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgForceSwimSpeedChange{guid: ^owner_guid, speed: 9.444444}}}

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.MsgMoveSetSwimSpeed{guid: ^owner_guid, speed: 9.444444}, _opts}}

      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgMoveSetSwimSpeed{}, _opts}}
    end

    test "raises for unsupported effects", %{mob: mob} do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(EventSink, :emit, [mob, %UnsupportedEffect{value: :unexpected}])
      end
    end

    test "instance data effects synchronously publish before pending emission returns", %{mob: mob} do
      {server, table, world} = instance_owner()
      effect = Effects.instance_data_command(world, 7, 1, :raw, 5_122)
      mob = %{mob | internal: %{mob.internal | world: world, events: [effect]}}

      assert %{internal: %{events: []}} = EventSink.emit_pending(mob, Context.new(self(), instance_system: server))
      assert %Snapshot{fields: %{7 => {:ok, 1}}} = InstanceData.read(world, [7], table)
    end

    test "instance owner rejection leaves all entity kinds alive and unchanged", %{mob: mob} do
      {server, table, world} = instance_owner()
      context = Context.new(self(), instance_system: server)
      effect = Effects.instance_data_command(world, 5, 2, :raw, 1_044_002)
      mob = %{mob | internal: %{mob.internal | world: world}}
      game_object = %GameObject{internal: %Internal{world: world}}
      character = %Character{internal: %Internal{world: world}}

      assert ^mob = EventSink.emit(mob, effect, context)
      assert ^game_object = EventSink.emit(game_object, effect, context)
      assert ^character = EventSink.emit(character, effect, context)
      assert Process.alive?(Process.whereis(server))
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(world, [7], table)
    end

    test "forced reaction changes update the client and request friendly attack cancellation" do
      character = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, unique_guid())},
        unit: %Unit{},
        player: %Player{},
        internal: %Internal{}
      }

      effect = Effects.forced_reactions_changed([{575, 4}], [575])

      assert ^character = EventSink.emit(character, effect, Context.new(self()))

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetForcedReactions{reactions: [{575, 4}]}}}

      assert_receive {:stop_attack_factions, [575]}
    end

    test "temporary at-war changes update the client" do
      character = %Character{
        object: %Object{guid: Guid.from_low_guid(:player, unique_guid())},
        unit: %Unit{},
        player: %Player{},
        internal: %Internal{}
      }

      assert ^character =
               EventSink.emit(character, Effects.faction_at_war_changed(13, true), Context.new(self()))

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetFactionAtwar{index: 13, enabled: true}}}
    end

    test "attacker_gained increments the target's attacker count", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Effects.attacker_gained(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 1}
    end

    test "attacker_lost decrements the target's attacker count", %{mob: mob, target_guid: target_guid} do
      Metadata.update(target_guid, %{attacker_count: 2})

      assert ^mob = EventSink.emit(mob, Effects.attacker_lost(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 1}
    end

    test "attacker_lost does not decrement below zero", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Effects.attacker_lost(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 0}
    end

    test "late engagement events do not resurrect removed target metadata", %{mob: mob, target_guid: target_guid} do
      Metadata.delete(target_guid)
      assert ^mob = EventSink.emit(mob, Effects.attacker_lost(target_guid))
      assert ^mob = EventSink.emit(mob, Effects.attacker_gained(target_guid))
      assert Metadata.get(target_guid) == nil
    end

    test "threat ref messages carry the mob incarnation" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(player_guid)

      on_exit(fn -> Entity.unregister(player_guid) end)

      mob = %Mob{object: %Object{guid: mob_guid}, internal: %Internal{spawn: %Spawn{incarnation_id: 7}}}

      assert ^mob = EventSink.emit(mob, Effects.threat_ref_gained(player_guid))
      assert_receive {:"$gen_cast", {:threat_ref_gained, ^mob_guid, 7}}
    end

    test "dismiss_pet stops the transitioned pet without mutating the owner" do
      character = character_with_pet()
      effect = Effects.dismiss_pet(character.unit.summon)

      assert ^character = EventSink.emit(character, effect)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
    end

    test "tap_cleared clears the entity's own tap metadata", %{mob: mob} do
      guid = mob.object.guid
      Metadata.update(guid, %{tapped_player: 123, tapped_group_id: 7})

      assert ^mob = EventSink.emit(mob, Effects.tap_cleared())
      assert Metadata.query(guid, [:tapped_player, :tapped_group_id]) == %{tapped_player: nil, tapped_group_id: nil}
    end

    test "tap_claimed projects typed tap ownership", %{mob: mob} do
      guid = mob.object.guid

      assert ^mob = EventSink.emit(mob, Effects.tap_claimed(123, 7))
      assert Metadata.query(guid, [:tapped_player, :tapped_group_id]) == %{tapped_player: 123, tapped_group_id: 7}
    end

    test "hearthstone teleports a character to their home bind" do
      home = %HomeBind{map_id: 0, area_id: 9, position: {-8_946.0, -132.0, 84.0}}
      character = %Character{internal: %Internal{world: %WorldRef{map_id: 1}, home_bind: home}}

      assert ^character = EventSink.emit(character, %Effects.TeleportHome{}, Context.new(self()))
      assert_receive {:"$gen_cast", {:start_teleport, -8_946.0, -132.0, 84.0, 0}}
    end

    test "teleport events preserve their orientation" do
      character = %Character{internal: %Internal{world: %WorldRef{map_id: 0}}}

      assert ^character = EventSink.emit(character, Effects.teleport({1.0, 2.0, 3.0, 1.5}), Context.new(self()))
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, 1.5, %WorldRef{map_id: 0}}}
    end

    test "feed-pet events preserve the DBC trigger and item target for the player boundary" do
      character = %Character{}
      event = Effects.feed_pet(22, 33, 1539, 10.0)

      assert ^character = EventSink.emit(character, event, Context.new(self()))
      assert_receive {:feed_pet, 22, 33, 1539, 10.0}
    end

    test "cancel auto repeat sends the empty client packet" do
      character = %Character{}

      assert ^character = EventSink.emit(character, Effects.cancel_auto_repeat(), Context.new(self()))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCancelAutoRepeat{}}}
    end

    test "spell modifier events send the matching client packet" do
      character = %Character{}

      context = Context.new(self())

      assert ^character = EventSink.emit(character, Effects.spell_modifier(:flat, 5, 10, -500), context)

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgSetFlatSpellModifier{effect_index: 5, operation: 10, value: -500}}}

      assert ^character = EventSink.emit(character, Effects.spell_modifier(:pct, 30, 10, 0), context)

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgSetPctSpellModifier{effect_index: 30, operation: 10, value: 0}}}
    end

    test "spell miss outcomes are delivered to the victim owner" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      mob = %Mob{object: %Object{guid: caster_guid}}
      spell = %Spell{id: 116, school: :frost}
      context = %CastContext{caster_guid: caster_guid, hit_outcome: :resist}
      event = Effects.deliver_spell(target_guid, context, spell)

      assert ^mob = EventSink.emit(mob, event)
      assert_receive {:"$gen_cast", {:receive_spell, %{caster_guid: ^caster_guid, hit_outcome: :resist}, ^spell}}
    end

    @tag :dbc_db
    test "a released judgement trigger delivers its encoded spell to the victim" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.trigger_spell(caster_guid, 60, target_guid, 20_187)

      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast",
                      {:receive_spell,
                       %CastContext{
                         caster_guid: ^caster_guid,
                         target_guid: ^target_guid
                       }, %Spell{id: 20_187}}}
    end

    @tag :dbc_db
    test "a custom trigger overrides the selected DBC effect points" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(caster_guid)
      on_exit(fn -> Entity.unregister(caster_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.trigger_spell(caster_guid, 60, caster_guid, 25_503, effect_index: 1, base_points: -16)

      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{}, %Spell{id: 25_503, effects: spell_effects}}}
      assert %{base_points: -16} = Enum.find(spell_effects, &(&1.index == 1))
    end

    @tag :dbc_db
    test "a resolved party trigger returns to the caster owner" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(caster_guid)
      on_exit(fn -> Entity.unregister(caster_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, health: 10, max_health: 1_000, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.trigger_spell(caster_guid, 60, caster_guid, 23_455, resolve_targets?: true)
      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{target_guid: ^caster_guid}, %Spell{id: 23_455}}}
    end

    @tag :dbc_db
    test "a DBC area trigger resolves hostile targets around its source" do
      caster_guid = Guid.from_low_guid(:mob, 5879, unique_guid())
      target_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(target_guid)
      SpatialHash.update(:players, target_guid, 0, 3.0, 0.0, 0.0)

      player_faction = %FactionTemplate{
        id: 1,
        faction: 1,
        flags: 72,
        faction_group: 3,
        friend_group: 2,
        enemy_group: 12
      }

      Metadata.put(target_guid, %{
        alive?: true,
        faction_template: player_faction,
        faction_can_have_reputation?: false,
        unit_flags: 0
      })

      on_exit(fn ->
        Entity.unregister(target_guid)
        SpatialHash.remove(:players, target_guid)
        Metadata.delete(target_guid)
      end)

      hostile_faction = %FactionTemplate{
        id: 17,
        faction: 15,
        flags: 1,
        faction_group: 8,
        friend_group: 0,
        enemy_group: 1,
        friends_0: 15
      }

      totem = %Mob{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, faction_template: hostile_faction},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert ^totem = EventSink.emit(totem, Effects.trigger_spell(caster_guid, 60, caster_guid, 8349))

      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{caster_guid: ^caster_guid}, %Spell{id: 8349}}}
    end

    @tag :dbc_db
    test "a remote command trigger stays targeted on the victim" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      victim = %Mob{
        object: %Object{guid: target_guid},
        unit: %Unit{
          level: 1,
          target: caster_guid,
          health: 1_000,
          max_health: 1_000,
          normal_resistance: 0
        },
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.trigger_spell(caster_guid, 60, target_guid, 20_467)

      assert ^victim = EventSink.emit(victim, event)

      assert_receive {:"$gen_cast",
                      {:receive_spell, %CastContext{caster_guid: ^caster_guid, target_guid: ^target_guid},
                       %Spell{id: 20_467}}}
    end

    @tag :dbc_db
    test "a local command proc snapshots weapon damage" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{
          level: 60,
          attack_power: 140,
          base_attack_time: 2_000,
          base_min_damage: 20.0,
          base_max_damage: 30.0,
          min_damage: 30.0,
          max_damage: 40.0
        },
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.trigger_spell(caster_guid, 60, target_guid, 20_424)

      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast",
                      {:receive_spell,
                       %CastContext{
                         caster_guid: ^caster_guid,
                         target_guid: ^target_guid,
                         weapon_base_min: 20.0,
                         weapon_base_max: 30.0,
                         attack_time_ms: 2_000
                       }, %Spell{id: 20_424}}}
    end

    @tag :dbc_db
    test "a summon-pet event starts an owned pet with the requested health" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(caster_guid)

      on_exit(fn -> Entity.unregister(caster_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 50, faction_template: 1, summon: 0},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = %{Effects.summon_pet(caster_guid, 416, 688) | health_percent: 15}

      assert ^caster = EventSink.emit(caster, event)

      assert_receive %Attachment{
        kind: :guardian,
        entity_ref: %EntityRef{guid: pet_guid, entry: 416, spell_id: 688},
        pid: pet_pid,
        spells: pet_spells,
        create: %UpdateObject{object: %Object{guid: pet_guid}, unit: %Unit{health: 83}}
      }

      assert pet_pid == Entity.pid(pet_guid)
      assert is_pid(Entity.pid(pet_guid))
      assert Enum.any?(pet_spells, &(&1.id == 11_762))

      on_exit(fn -> World.stop_entity(pet_guid) end)
    end

    test "NPC pet summons reach the explicit owner context", %{mob: mob} do
      parent = self()
      receiver = spawn(fn -> receive do: (message -> send(parent, {:forwarded, message})) end)
      event = Effects.summon_pet(mob.object.guid, 10_928, 8722)
      assert ^mob = EventSink.emit(mob, event, Context.new(receiver))
      assert_receive {:forwarded, ^event}
      refute_receive ^event, 0
    end

    test "script attack_start schedules a forced attack", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Effects.attack_start(target_guid), Context.new(self()))
      assert_receive {:force_attack, ^target_guid}
    end

    test "owner commands use the explicit context instead of the emitting process", %{
      mob: mob,
      target_guid: target_guid
    } do
      receiver = self()

      Task.await(
        Task.async(fn ->
          EventSink.emit(mob, Effects.attack_start(target_guid), Context.new(receiver))
        end)
      )

      assert_receive {:force_attack, ^target_guid}
    end

    test "control transitions notify the controlling entity", %{mob: mob} do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(owner_guid)
      Entity.register(mob.object.guid)

      on_exit(fn ->
        Entity.unregister(owner_guid)
        Entity.unregister(mob.object.guid)
      end)

      spell = %Spell{id: 3110}

      assert ^mob = EventSink.emit(mob, Effects.control_granted(owner_guid, mob.object.guid, 20_882, [spell]))

      assert_receive %Attachment{
        kind: :charm,
        entity_ref: %EntityRef{guid: controlled_guid, spell_id: 20_882},
        pid: controlled_pid,
        spells: [^spell],
        create: nil
      }

      assert controlled_guid == mob.object.guid
      assert controlled_pid == self()

      assert ^mob = EventSink.emit(mob, Effects.control_released(owner_guid, mob.object.guid))
      assert_receive {:control_released, ^controlled_guid}
    end

    test "drop_nearby_threat reconciles mobs missing from player threat refs" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(mob_guid)
      SpatialHash.update(:mobs, mob_guid, 0, 10.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(mob_guid)
        SpatialHash.remove(:mobs, mob_guid)
      end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{level: 60, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert ^character = EventSink.emit(character, Effects.drop_nearby_threat())
      assert_receive {:"$gen_cast", {:drop_threat, ^player_guid}}
    end

    test "attacker_state_update broadcasts landed hits as normal victim state", %{target_guid: target_guid} do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Entity.register(player_guid)
      SpatialHash.update(:players, player_guid, 0, 0.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(player_guid)
        SpatialHash.remove(:players, player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      for {mask, school} <- [{1, 0}, {4, 2}, {16, 4}, {32, 5}] do
        attack = %{spell_school_mask: mask, absorb: 3, resist: 4}
        EventSink.emit(mob, Effects.attacker_state_update(mob_guid, target_guid, 12, attack))

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.SmsgAttackerstateupdate{
                           attacker: ^mob_guid,
                           target: ^target_guid,
                           total_damage: 12,
                           damage_state: 1,
                           damages: [%{school: ^school, absorb: 3, resist: 4}]
                         }, _opts}}
      end
    end

    test "periodic_aura_log broadcasts periodic aura log packets", %{target_guid: target_guid} do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Entity.register(player_guid)
      SpatialHash.update(:players, player_guid, 0, 0.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(player_guid)
        SpatialHash.remove(:players, player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Effects.periodic_aura_log(mob_guid, target_guid, %{id: 139}, :periodic_heal, 25)

      EventSink.emit(mob, event)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgPeriodicauralog{
                         target: ^target_guid,
                         caster: ^mob_guid,
                         spell_id: 139,
                         auras: [%{aura_type: :periodic_heal, amount: 25, misc_value: 0}]
                       }, _opts}}
    end

    test "periodic heals report a helpful periodic outcome to the caster", %{mob: mob, target_guid: target_guid} do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(caster_guid)

      on_exit(fn -> Entity.unregister(caster_guid) end)

      spell = %Spell{id: 139, school: :holy}
      event = Effects.spell_heal(caster_guid, target_guid, spell, 25, false, periodic?: true)

      assert ^mob = EventSink.emit(mob, event)

      assert_receive {:"$gen_cast",
                      {:spell_outcome,
                       %{
                         victim_guid: ^target_guid,
                         outcome: :normal,
                         damage: 25,
                         proc_type: :deal_helpful_periodic,
                         spell_id: 139
                       }}}
    end
  end

  defp instance_owner do
    server = :"event_sink_instance_#{System.unique_integer([:positive])}"
    table = :ets.new(:event_sink_instance_data, [:set, :public, read_concurrency: true])

    start_supervised!(
      {InstanceSystem,
       name: server,
       projection_table: table,
       script_name: fn 329 -> "instance_stratholme" end,
       owner: fn guid -> {:player, guid} end}
    )

    guid = System.unique_integer([:positive])
    {:ok, world} = InstanceSystem.enter(329, guid, server)
    {server, table, world}
  end

  defp metadata_fixtures(_context) do
    mob_guid = unique_guid()
    target_guid = unique_guid()

    Metadata.put(mob_guid, %{})
    Metadata.put(target_guid, %{attacker_count: 0})

    on_exit(fn ->
      Metadata.delete(mob_guid)
      Metadata.delete(target_guid)
    end)

    %{mob: %Mob{object: %Object{guid: mob_guid}}, target_guid: target_guid}
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end

  defp character_with_pet do
    pet_guid = Guid.from_low_guid(:pet, 416, unique_guid())

    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, unique_guid())},
      player: %Player{},
      unit: %Unit{},
      internal: %Internal{}
    }
    |> Companion.activate(:guardian, %EntityRef{guid: pet_guid, entry: 416, spell_id: 688})
  end
end
