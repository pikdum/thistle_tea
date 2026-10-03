defmodule ThistleTea.Game.Core.GameEvent.ElementalInvasion do
  @moduledoc """
  The Elemental Invasion (vmangos `ElementalInvasion`, hardcoded game event
  13, with its rift and invader scripts). Rifts in Un'Goro, Silithus,
  Azshara, and Winterspring pour invaders into their zones, more of them as
  each element's stage climbs: one stage for every fifty invaders slain or
  every hour endured, until the element's lord walks out at the boss stage.
  A lord's death closes its rifts and, after a looting grace, ends its own
  event; once all four lords have fallen the invasion rests for two to four
  days.

  The calendar never starts these events. `World.System.ElementalInvasion`
  drives them from the stage each element's server variable holds, the same
  variable its lord's EventAI marks on death.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion.Element
  alias ThistleTea.Game.Core.GameEvent.Rule

  @invasion 13
  @first_stage 1
  @boss_stage 5
  @boss_down 6
  @kills_per_stage 50
  @fewest_invaders 3
  @most_invaders 6
  @rest_ms (2 * 24 * 3_600_000)..(4 * 24 * 3_600_000)

  @elements [
    %Element{
      name: :fire,
      rift_event: 68,
      boss_event: 72,
      rift: 179_666,
      invader: 14_460,
      stage_variable: 30_008,
      kills_variable: 30_012
    },
    %Element{
      name: :air,
      rift_event: 69,
      boss_event: 73,
      rift: 179_667,
      invader: 14_455,
      stage_variable: 30_011,
      kills_variable: 30_015
    },
    %Element{
      name: :earth,
      rift_event: 70,
      boss_event: 74,
      rift: 179_664,
      invader: 14_462,
      stage_variable: 30_010,
      kills_variable: 30_014
    },
    %Element{
      name: :water,
      rift_event: 71,
      boss_event: 75,
      rift: 179_665,
      invader: 14_458,
      stage_variable: 30_009,
      kills_variable: 30_013
    }
  ]

  @impl Rule
  def events, do: [@invasion | Enum.flat_map(@elements, &[&1.rift_event, &1.boss_event])]

  @impl Rule
  def active_events(%DateTime{}, _scheduled), do: []

  @impl Rule
  def boundaries(%DateTime{}), do: []

  def elements, do: @elements

  def summon_entries, do: Enum.map(@elements, & &1.invader)

  def first_stage, do: @first_stage

  def rest_ms, do: @rest_ms

  def rift_element(entry), do: Enum.find(@elements, &(&1.rift == entry))

  def stage_element(variable), do: Enum.find(@elements, &(&1.stage_variable == variable))

  def invaders(stage) when stage in @first_stage..@boss_stage//1, do: min(@fewest_invaders + stage - 1, @most_invaders)

  def invaders(_stage), do: 0

  def slain(stage, kills) when stage in @first_stage..(@boss_stage - 1)//1 do
    if kills + 1 >= @kills_per_stage, do: {stage + 1, 0}, else: {stage, kills + 1}
  end

  def slain(stage, kills), do: {stage, kills}

  def endured(stage) when stage in @first_stage..(@boss_stage - 1)//1, do: stage + 1
  def endured(stage), do: stage

  def boss_down?(stage), do: stage == @boss_down

  def driven(stages, looting) when is_map(stages) do
    invading? = Enum.any?(@elements, &(Map.fetch!(stages, &1.name) < @boss_down or &1.name in looting))

    Enum.reduce(@elements, %{@invasion => invading?}, fn element, events ->
      stage = Map.fetch!(stages, element.name)
      boss? = stage == @boss_stage or (stage == @boss_down and element.name in looting)

      events
      |> Map.put(element.rift_event, invading? and stage < @boss_down)
      |> Map.put(element.boss_event, invading? and boss?)
    end)
  end
end
