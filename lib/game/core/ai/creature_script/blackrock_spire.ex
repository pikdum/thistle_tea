defmodule ThistleTea.Game.Core.AI.CreatureScript.BlackrockSpire do
  @moduledoc """
  vmangos's Blackrock Spire boss AIs: `boss_highlord_omokk`,
  `boss_shadow_hunter_voshgajin`, `boss_warmaster_voone`,
  `boss_overlord_wyrmthalak`, `boss_halycon`, `boss_the_beast`, and the
  `npc_blackhand_veteran` guarding the Hall of Blackhand.

  Each fights with its own timed abilities. War Master Voone throws his axes
  until he has none left, then fights barehanded, faster and weaker. Overlord
  Wyrmthalak calls a Spirestone Warlord and a Smolderthorn Berserker once he
  drops to half health, and Halycon's death draws Gizrul the Slavener out to
  avenge her. The Beast wreathes itself in flame and charges its victim
  first, then other attackers.

  A veteran's Shield Bash goes to its victim instead of whichever attacker
  is casting, and Voone's weapons change as he throws rather than when the
  axe lands. Voone takes his axes back when he leaves the fight, where
  vmangos leaves him barehanded.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep

  @omokk 9_196
  @voshgajin 9_236
  @voone 9_237
  @wyrmthalak 9_568
  @halycon 10_220
  @the_beast 10_430
  @blackhand_veteran 9_819

  @spirestone_warlord 9_216
  @smolderthorn_berserker 9_268
  @gizrul 10_268

  @triggered 0x02
  @random_target 4
  @timed_out_of_combat_despawn 4
  @dead_despawn 7
  @rally 1

  @halycon_howl "Halycon lets loose a gutteral growl as her body collapses. A horrifying howl can be heard echoing " <>
                  "through the halls of Blackrock Spire. Something is very, very angry."

  @impl CreatureScript
  def entries, do: [@omokk, @voshgajin, @voone, @wyrmthalak, @halycon, @the_beast, @blackhand_veteran]

  @impl CreatureScript
  def events(@omokk = entry) do
    [
      Combat.every(entry, 1, Combat.cast(24_375, :self), 15_000, 14_000),
      Combat.every(entry, 2, Combat.cast(18_368), 10_000, 10_000),
      Combat.every(entry, 3, Combat.cast(18_106), 14_000, 18_000),
      Combat.every(entry, 4, Combat.cast(24_317), 2_000, 25_000),
      Combat.every(entry, 5, Combat.cast(20_686, :self), 18_000, 12_000),
      Combat.every(entry, 6, Combat.cast(22_356, :self), 24_000, 18_000)
    ]
  end

  def events(@voshgajin = entry) do
    [
      Combat.every(entry, 1, Combat.cast(24_673, :self), 2_000, 45_000),
      Combat.every(entry, 2, Combat.cast(16_708, :hostile_random), 8_000, 15_000),
      Combat.every(entry, 3, Combat.cast(20_691), 14_000, 7_000)
    ]
  end

  def events(@voone = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_618), 8_000, 6_000),
      Combat.every(entry, 2, Combat.cast(15_284), 14_000, 12_000),
      Combat.every(entry, 3, Combat.cast(10_966), 20_000, 14_000),
      Combat.every(entry, 4, Combat.cast(15_708), 12_000, 10_000),
      Combat.every(entry, 5, Combat.cast(15_615), 32_000, 16_000),
      Combat.every(entry, 6, throw_axe(1, [equipment(12_348)]), 1_000, 8_000, in_phase(0)),
      Combat.every(
        entry,
        7,
        throw_axe(2, [equipment(0), Combat.cast(16_076, :self, @triggered)]),
        9_000,
        8_000,
        in_phase(1)
      ),
      CreatureScript.event(entry, 8, :evade, [%ScriptStep{command: :set_equipment, datalong: 1}])
    ]
  end

  def events(@wyrmthalak = entry) do
    [
      Combat.every(entry, 1, Combat.cast(11_130, :self), 20_000, 20_000),
      Combat.every(entry, 2, Combat.cast(23_511, :self), 2_000, 10_000),
      Combat.every(entry, 3, Combat.cast(20_691), 6_000, 7_000),
      Combat.every(entry, 4, Combat.cast(20_686, :self), 12_000, 14_000),
      CreatureScript.event(
        entry,
        5,
        :hp,
        [
          reinforcement(@spirestone_warlord, {-39.355381, -513.456482, 88.472046, 4.679872}),
          reinforcement(@smolderthorn_berserker, {-49.875881, -511.89694, 88.19516, 4.613114})
        ],
        param1: 51,
        repeatable?: false
      )
    ]
  end

  def events(@halycon = entry) do
    [
      Combat.every(entry, 1, Combat.cast(10_887), 8_000, 14_000),
      Combat.every(entry, 2, Combat.cast(14_099), 14_000, 10_000),
      CreatureScript.event(entry, 3, :death, [Combat.text_emote(@halycon_howl), summon_gizrul()], repeatable?: false)
    ]
  end

  def events(@the_beast = entry) do
    immolate = Combat.cast(15_506, :self, @triggered)

    [
      CreatureScript.event(entry, 1, :spawned, [immolate]),
      CreatureScript.event(entry, 2, :reached_home, [immolate]),
      Combat.every(entry, 3, Combat.cast(16_785, :self), {8_000, 12_000}, {14_000, 20_000}),
      Combat.every(entry, 4, Combat.cast(14_100, :self), 13_000, {16_000, 18_000}),
      Combat.every(entry, 5, Combat.cast(16_636), 0, 0, repeatable?: false),
      Combat.every(entry, 6, Combat.cast(16_636, :hostile_random_not_top), {15_000, 20_000}, {15_000, 20_000}),
      Combat.every(entry, 7, Combat.cast(16_788, :hostile_random_not_top), 10_000, {10_000, 12_000}),
      Combat.every(entry, 8, Combat.cast(14_144), {8_000, 11_000}, {14_000, 20_000})
    ]
  end

  def events(@blackhand_veteran = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_749), 0, 0, repeatable?: false),
      Combat.every(entry, 2, Combat.cast(15_749, :hostile_random), {8_000, 14_000}, {8_000, 14_000}),
      Combat.every(entry, 3, Combat.cast(11_972), 2_000, 10_000),
      Combat.every(entry, 4, Combat.cast(14_516, :hostile_random), 5_000, 6_000)
    ]
  end

  defp throw_axe(next_phase, swap) do
    [Combat.cast(16_075) | swap] ++ [%ScriptStep{command: :set_phase, datalong: next_phase}]
  end

  defp equipment(main_hand), do: %ScriptStep{command: :set_equipment, dataint: main_hand, dataint3: -1}

  defp in_phase(phase), do: [inverse_phase_mask: CreatureScript.only_in_phases([phase])]

  defp reinforcement(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: 10_000,
      dataint3: @random_target,
      dataint4: @timed_out_of_combat_despawn,
      position: position
    }
  end

  defp summon_gizrul do
    %ScriptStep{
      command: :summon_creature,
      datalong: @gizrul,
      dataint2: @rally,
      dataint3: -1,
      dataint4: @dead_despawn,
      position: {-167.58, -382.41, 64.401, 1.563},
      sub_scripts: %{
        @rally => [
          %ScriptStep{command: :set_home_position, position: {-172.633, -324.253, 64.401, 4.74}},
          %ScriptStep{command: :zone_combat_pulse, datalong: 1}
        ]
      }
    }
  end
end
