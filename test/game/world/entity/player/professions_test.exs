defmodule ThistleTea.Game.World.Entity.Player.ProfessionsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Skills
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Professions
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Inbound
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  setup [:character]

  describe "unlearn/2" do
    test "the registered packet removes spells and tracking, frees the slot, and persists", %{state: state} do
      packet = %Packet{opcode: Opcodes.get(:CMSG_UNLEARN_SKILL), payload: <<186::little-size(32)>>}
      assert Dispatch.implemented?(packet.opcode)
      assert %Message.CmsgUnlearnSkill{skill_id: 186} = message = Dispatch.to_message(packet)
      changed = Inbound.handle(message, state)
      refute Skills.known?(changed.character.player.skills, 186)
      assert Skills.known?(changed.character.player.skills, 182)
      assert Skills.free_profession_slots(changed.character.player.skills) == 1
      assert changed.character.internal.spells == [999_102]
      assert Map.keys(changed.character.internal.spellbook) == [999_102]
      assert changed.character.player.track_resources == 0
      assert changed.character.unit.auras == []
      refute Map.has_key?(changed.character.internal.forgotten_skills, 186)
      assert CharacterStore.get(state.guid).player.skills == changed.character.player.skills
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: 999_100}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: 999_101}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: 999_102}}}
      assert Professions.unlearn(changed, 186) == changed
      retrained = Skills.learn_rank(changed.character.player.skills, 186, 75)
      assert retrained[186].value == 1
      assert retrained[186].max == 75
    end

    test "cancels a removed craft with failure feedback", %{state: state} do
      spell = state.character.internal.spellbook[999_101]
      cast = %Cast{spell: spell, ends_at: 100_000}
      state = %{state | character: %{state.character | internal: %{state.character.internal | casting: cast}}}
      changed = Professions.unlearn(state, 186)
      assert changed.character.internal.casting == nil
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 999_101, result: 2}}}
    end

    test "preserves unrelated casting and rejects protected skills and wrong race", %{state: state} do
      cast = %Cast{spell: state.character.internal.spellbook[999_102]}
      state = %{state | character: %{state.character | internal: %{state.character.internal | casting: cast}}}
      assert Professions.unlearn(state, 43) == state
      assert Professions.unlearn(state, 0) == state
      wrong_race = %{state | character: %{state.character | unit: %{state.character.unit | race: 2}}}
      assert Professions.unlearn(wrong_race, 186) == wrong_race
      changed = Professions.unlearn(state, 186)
      assert changed.character.internal.casting == cast

      assert Inbound.handle(%Message.CmsgUnlearnSkill{skill_id: 186}, %{state | ready: false}) ==
               %{state | ready: false}
    end
  end

  defp character(_context) do
    keys = [{:info, 186}, {:abilities, 186}, {:spell_skills, 999_100}, {:spell_skills, 999_101}]
    previous = Enum.flat_map(keys, &:ets.lookup(SkillLoader, &1))

    SkillLoader.load(
      [],
      [%DBC.SkillRaceClassInfo{skill_line: 186, race_mask: 1, class_mask: 1, flags: 0x20}],
      Enum.map([999_100, 999_101], &%DBC.SkillLineAbility{skill_line: 186, spell: &1})
    )

    skills = %{} |> Skills.learn_rank(186, 300) |> Skills.learn_rank(182, 75)
    skills = Map.update!(skills, 186, &%{&1 | value: 250})

    tracking = %Spell{
      id: 999_100,
      school: :physical,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :track_resources, misc_value: 2, base_points: 0}]
    }

    spells = [tracking, %Spell{id: 999_101}, %Spell{id: 999_102}]

    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{skills: skills},
        internal: %Internal{
          spells: Enum.map(spells, & &1.id),
          spellbook: Map.new(spells, &{&1.id, &1}),
          forgotten_skills: skills
        },
        unit: %Unit{race: 1, class: 1, level: 60, health: 100, max_health: 100, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      })

    {character, _events} = Aura.apply_spell(character, character.object.guid, 60, tracking, 1_000)
    guid = character.object.guid
    {:ok, _} = Entity.register(guid)

    on_exit(fn ->
      Enum.each(keys, &:ets.delete(SkillLoader, &1))
      :ets.insert(SkillLoader, previous)
      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
      SpatialHash.remove(:players, guid)
    end)

    %{state: %State{guid: guid, ready: true, character: character}}
  end
end
