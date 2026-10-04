defmodule ThistleTea.Game.Core.AI.CreatureScript.LadyJainaProudmoore do
  @moduledoc """
  vmangos `npc_lady_jaina_proudmoore`, the ruler of Theramore in Foothold
  Citadel.

  She welcomes visitors to Theramore, or speaks of Hendel's capture to a
  player who has finished The Missing Diplomat (1267). A player on Jaina's
  Autograph (558), the Children's Week errand, may ask for her autograph:
  she agrees, and the player signs for it with Jaina's Autograph (23122),
  which makes the item the orphan matron wants.

  In combat she sounds her battle cry and casts Fireball or Fire Blast at
  her victim, or a Blizzard on a random attacker, every 3 to 10 seconds,
  and her timers wait while she is casting.
  Every 10 to 30 seconds she either calls her water elementals, about one
  time in five and only while none are near, or teleports her victim back
  to the top of her tower. When she has been drawn more than 40 yards from
  that spot, the teleported player leaves her threat list.

  vmangos hands a player one step short of Hendel's capture her quest list
  in place of a greeting. This port greets them as it greets everyone, with
  her quests below.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @jaina 4_968
  @water_elemental 10_955

  @jainas_autograph 558
  @missing_diplomat 1_267
  @incomplete 1
  @complete 2

  @fireball 20_678
  @fire_blast 20_679
  @blizzard 20_680
  @summon_water_elementals 20_681
  @teleport 20_682
  @autograph 23_122

  @battle_cry 5_882
  @distance_dependent 0x2

  @welcome_text 3_157
  @hendel_text 3_158
  @autograph_text 7_012
  @ask_autograph "I know this is rather silly but i have a young ward who is a bit shy and would like your autograph."

  @tower {-4_018.1, -4_525.24, 12.0}
  @tower_reach 40
  @elemental_reach 100
  @victim 1
  @drop_threat -101.0

  @impl CreatureScript
  def entries, do: [@jaina]

  @impl CreatureScript
  def events(@jaina) do
    [
      CreatureScript.event(@jaina, 1, :aggro, [
        %ScriptStep{command: :play_sound, datalong: @battle_cry, datalong2: @distance_dependent}
      ]),
      CreatureScript.event(@jaina, 2, :timer_in_combat, spell(), timer({3_000, 3_000}, {3_000, 10_000})),
      CreatureScript.event(@jaina, 3, :timer_in_combat, special(), timer({15_000, 15_000}, {10_000, 30_000}))
    ]
  end

  @impl CreatureScript
  def gossip do
    %{
      @jaina => %Gossip{
        texts: [%Gossip.Text{text_id: @welcome_text}, %Gossip.Text{text_id: @hendel_text, condition: hendel_caught()}],
        options: [
          %Gossip.Option{
            text: @ask_autograph,
            condition: %Condition{type: :quest_taken, value1: @jainas_autograph, value2: @incomplete},
            reply_text_id: @autograph_text,
            steps: [%ScriptStep{command: :cast_spell, datalong: @autograph, swap_final?: true, target_self?: true}]
          }
        ]
      }
    }
  end

  defp spell do
    CreatureScript.pick_weighted([
      {2, [cast_at(@fireball, :victim)]},
      {2, [cast_at(@fire_blast, :victim)]},
      {1, [cast_at(@blizzard, :hostile_random)]}
    ])
  end

  defp special do
    CreatureScript.pick_weighted([
      {1, [%{cast_at(@summon_water_elementals, :provided) | target_self?: true, condition: no_elementals()}]},
      {4, [cast_at(@teleport, :victim), drop_victim_away_from_tower()]}
    ])
  end

  defp drop_victim_away_from_tower do
    {x, y, z} = @tower

    %ScriptStep{
      command: :modify_threat,
      datalong: @victim,
      position: {@drop_threat, 0.0, 0.0, 0.0},
      condition: %Condition{
        type: :distance_to_position,
        value1: x,
        value2: y,
        value3: z,
        value4: @tower_reach,
        swap_targets?: true,
        reverse?: true
      }
    }
  end

  defp no_elementals,
    do: %Condition{type: :nearby_creature, value1: @water_elemental, value2: @elemental_reach, reverse?: true}

  defp hendel_caught do
    %Condition{
      type: :or,
      children: [
        %Condition{type: :quest_rewarded, value1: @missing_diplomat},
        %Condition{type: :quest_taken, value1: @missing_diplomat, value2: @complete}
      ]
    }
  end

  defp cast_at(spell_id, target_type),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: target_type}

  defp timer({initial_min, initial_max}, {repeat_min, repeat_max}),
    do: [param1: initial_min, param2: initial_max, param3: repeat_min, param4: repeat_max, not_casting?: true]
end
