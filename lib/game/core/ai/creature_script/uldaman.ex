defmodule ThistleTea.Game.Core.AI.CreatureScript.Uldaman do
  @moduledoc """
  vmangos `boss_archaedas`, `boss_ironaya`, `mob_stone_keeper`, and the
  fighting half of `mob_archaedas_minions`, the stone guardians of Uldaman.

  Archaedas stands as untouchable stone until his altar wakes him
  (`InstanceScript.Uldaman`). In the fight he shakes the ground every 45
  seconds after the first minute, and every ten seconds tells the copy to
  wake another of the earthen on the walls. At two thirds health he calls
  the Earthen Guardians and at a third the Vault Warders. When he gives up
  the fight he cannot be targeted on his walk home, where he turns back to
  stone and lets the copy put his chamber back to sleep. His death raises
  the Ancient Treasure at the far end of his chamber.

  Ironaya smashes the ground around her, knocks her victim away once below
  half health and forgets it, and stomps once below a quarter. The Stone
  Keepers and Vault Warders trample, and the Earthen Custodians reconstruct
  Archaedas every ten seconds while he is below half health.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @archaedas 2_748
  @ironaya 7_228
  @stone_keeper 4_857
  @earthen_custodian 7_309
  @vault_warder 10_120

  @ground_tremor 6_524
  @awaken_earthen_guardians 10_252
  @awaken_vault_warder 10_258
  @stoned 10_255
  @arcing_smash 8_374
  @knock_away 10_101
  @war_stomp 11_876
  @trample 5_568
  @reconstruct 10_260

  @say_summon_guardians 6_536
  @say_summon_warders 6_537
  @say_slay 6_215
  @say_ironaya_aggro 3_261

  @archaedas_field 2
  @guardians_awaken 13
  @vault_warders_awaken 14
  @not_started 0
  @in_progress 1

  @ancient_treasure 141_979
  @treasure_position {153.39, 289.091, -52.2262, 2.68781}
  @unattached 1

  @unit_flags 46
  @frozen 0x02000300
  @not_selectable 0x02000000
  @add_flags 1
  @triggered 0x02
  @victim 1
  @reconstruct_reach 100
  @below 2

  @impl CreatureScript
  def entries, do: [@archaedas, @ironaya, @stone_keeper, @earthen_custodian, @vault_warder]

  @impl CreatureScript
  def events(@archaedas = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, turn_to_stone()),
      CreatureScript.event(entry, 2, :evade, [flags(@not_selectable)]),
      CreatureScript.event(entry, 3, :reached_home, [instance_data(@archaedas_field, @not_started) | turn_to_stone()]),
      CreatureScript.event(entry, 4, :timer_in_combat, [instance_data(@archaedas_field, @in_progress)], timer(10_000)),
      CreatureScript.event(entry, 5, :timer_in_combat, [cast_self(@ground_tremor)], timer(60_000, 45_000)),
      CreatureScript.event(
        entry,
        6,
        :hp,
        [
          cast_self(@awaken_earthen_guardians),
          talk(@say_summon_guardians),
          instance_data(@guardians_awaken, @in_progress)
        ],
        param1: 66,
        repeatable?: false
      ),
      CreatureScript.event(
        entry,
        7,
        :hp,
        [
          talk(@say_summon_warders),
          instance_data(@vault_warders_awaken, @in_progress),
          cast_self(@awaken_vault_warder)
        ],
        param1: 33,
        repeatable?: false
      ),
      CreatureScript.event(entry, 8, :kill, [talk(@say_slay)]),
      CreatureScript.event(entry, 9, :death, [
        %ScriptStep{
          command: :summon_object,
          datalong: @ancient_treasure,
          datalong3: @unattached,
          position: @treasure_position
        }
      ])
    ]
  end

  def events(@ironaya = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(@say_ironaya_aggro), %ScriptStep{command: :zone_combat_pulse}]),
      CreatureScript.event(entry, 2, :timer_in_combat, [cast_self(@arcing_smash)], timer(13_000)),
      CreatureScript.event(
        entry,
        3,
        :hp,
        [
          cast_victim(@knock_away),
          %ScriptStep{command: :modify_threat, datalong: @victim, position: {-100.0, 0.0, 0.0, 0.0}}
        ],
        param1: 49,
        repeatable?: false
      ),
      CreatureScript.event(entry, 4, :hp, [cast_self(@war_stomp)], param1: 24, repeatable?: false)
    ]
  end

  def events(@stone_keeper = entry),
    do: [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_self(@trample)], timer({4_000, 9_000}, {4_000, 10_000}))
    ]

  def events(@vault_warder = entry),
    do: [CreatureScript.event(entry, 1, :timer_in_combat, [cast_self(@trample)], timer({4_000, 10_000}, 10_000))]

  def events(@earthen_custodian = entry) do
    reconstruct = %ScriptStep{
      command: :cast_spell,
      datalong: @reconstruct,
      target_type: :nearest_creature_with_entry,
      target_param1: @archaedas,
      target_param2: @reconstruct_reach,
      condition: %Condition{type: :health_percent, value1: 49, value2: @below}
    }

    [CreatureScript.event(entry, 1, :timer_in_combat, [reconstruct], timer({4_000, 10_000}, 10_000))]
  end

  def events(_entry), do: []

  defp turn_to_stone, do: [flags(@frozen), cast_self(@stoned, @triggered)]

  defp flags(mask),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: mask, datalong3: @add_flags}

  defp instance_data(field, value), do: %ScriptStep{command: :set_instance_data, datalong: field, datalong2: value}

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  defp timer(every_ms), do: timer(every_ms, every_ms)

  defp timer(initial, repeat) do
    {initial_min, initial_max} = range(initial)
    {repeat_min, repeat_max} = range(repeat)
    [param1: initial_min, param2: initial_max, param3: repeat_min, param4: repeat_max]
  end

  defp range({min_ms, max_ms}), do: {min_ms, max_ms}
  defp range(ms), do: {ms, ms}
end
