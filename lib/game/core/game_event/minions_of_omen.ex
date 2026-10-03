defmodule ThistleTea.Game.Core.GameEvent.MinionsOfOmen do
  @moduledoc """
  vmangos `boss_omen`'s watch over Elune's lake in Moonglade, which drives
  the hardcoded Lunar Festival event 43, Minions of Omen. Fireworks sent up
  from Omen's cluster launchers wake the lake: the third brings his minions
  out, and the twentieth calls Omen himself up from the water, unless he
  fell less than fifteen minutes ago. While Omen is out the launches go
  uncounted. The minions stay until Omen leaves the world.

  If Omen never arrives, the watch lets the call go and keeps counting.

  The calendar never starts the event. `World.System.MinionsOfOmen` keeps
  the watch and drives the event through `World.System.GameEvent.drive/2`.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule

  @minions_of_omen 43
  @omen 15_467
  @launcher 180_874
  @minions_at 3
  @omen_at 20
  @rest_ms 15 * 60_000
  @omen_lifetime_ms 2 * 3_600_000
  @timed_combat_or_dead 9
  @rises_at {7_560.01, -2_838.36, 449.575, 4.01426}
  @home {7_542.5, -2_870.67, 459.498, 1.13905}
  @wander_distance 10.0

  defstruct fireworks: 0, omen_out?: false, minions?: false, rests_until: nil

  @impl Rule
  def events, do: [@minions_of_omen]

  @impl Rule
  def active_events(%DateTime{}, _scheduled), do: []

  @impl Rule
  def boundaries(%DateTime{}), do: []

  def omen, do: @omen

  def summon_entries, do: [@omen]

  def launcher, do: @launcher

  def launched(%__MODULE__{omen_out?: true} = watch, _now), do: {watch, false}

  def launched(%__MODULE__{} = watch, now) when is_integer(now) do
    fireworks = watch.fireworks + 1
    watch = %{watch | fireworks: fireworks, minions?: watch.minions? or fireworks >= @minions_at}

    if fireworks >= @omen_at and rested?(watch, now),
      do: {%{watch | fireworks: 0, omen_out?: true}, true},
      else: {watch, false}
  end

  def fell(%__MODULE__{} = watch, now) when is_integer(now),
    do: %{watch | omen_out?: false, rests_until: now + @rest_ms}

  def missed(%__MODULE__{} = watch), do: %{watch | omen_out?: false}

  def gone(%__MODULE__{} = watch), do: %{watch | omen_out?: false, minions?: false}

  def driven(%__MODULE__{minions?: minions?}), do: %{@minions_of_omen => minions?}

  def summon do
    %{
      entry: @omen,
      position: @rises_at,
      despawn_type: @timed_combat_or_dead,
      despawn_delay_ms: @omen_lifetime_ms,
      run?: true,
      unique?: false,
      attack_guid: nil,
      script_id: 0,
      home: @home,
      wander_distance: @wander_distance
    }
  end

  defp rested?(%__MODULE__{rests_until: nil}, _now), do: true
  defp rested?(%__MODULE__{rests_until: rests_until}, now), do: now >= rests_until
end
