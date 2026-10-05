defmodule ThistleTea.Game.Core.Battleground.AlteracValley.Beacon do
  @moduledoc "Alterac beacon factions and the single transition from waiting to disabled or summoned."

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal.Summon
  alias ThistleTea.Game.Core.Entity.GameObject

  defstruct [:team, :ready_at, status: :waiting]

  @horde [178_545, 178_547, 178_549]
  @alliance [178_724, 178_725, 178_726]
  @plant_spells %{
    21_355 => :horde,
    21_370 => :horde,
    21_371 => :horde,
    21_728 => :alliance,
    21_729 => :alliance,
    21_730 => :alliance
  }

  def entry?(entry), do: entry in @horde or entry in @alliance
  def plant_spells, do: @plant_spells
  def team(entry) when entry in @horde, do: :horde
  def team(entry) when entry in @alliance, do: :alliance
  def team(_entry), do: nil

  def prepare(
        %GameObject{
          object: %{entry: entry},
          internal: %{summon: %Summon{}, world: %{map_id: 30, instance_id: id}} = internal
        } = object,
        now
      )
      when is_integer(id) and (entry in @horde or entry in @alliance) do
    beacon = %__MODULE__{team: team(entry), ready_at: now + 60_000}
    summon = %{internal.summon | owner_guid: nil, owner_pid: nil, despawn_in_ms: nil}
    fields = %{object.game_object | created_by: nil, level: 0, faction: if(beacon.team == :alliance, do: 83, else: 84)}
    %{object | game_object: fields, internal: %{internal | beacon: beacon, summon: summon}}
  end

  def prepare(%GameObject{} = object, _now), do: object

  def disable(
        %GameObject{internal: %{beacon: %__MODULE__{status: :waiting, team: team, ready_at: at} = beacon} = internal} =
          object,
        opponent,
        now
      )
      when opponent in [:alliance, :horde] and opponent != team and now < at do
    {:ok, %{object | internal: %{internal | beacon: %{beacon | status: :disabled}}}}
  end

  def disable(%GameObject{} = object, _team, _now), do: {:error, object}

  def summon(
        %GameObject{internal: %{beacon: %__MODULE__{status: :waiting, ready_at: at} = beacon} = internal} = object,
        now
      )
      when now >= at do
    {x, y, z, orientation} = object.movement_block.position

    creature = %{
      entry: if(beacon.team == :alliance, do: 13_161, else: 13_178),
      position: {x, y, z + 30.0, orientation},
      despawn_type: 5,
      despawn_delay_ms: 10_000,
      run?: true,
      unique?: false,
      attack_guid: nil,
      script_id: 0
    }

    object = %{object | internal: %{internal | beacon: %{beacon | status: :summoned}}}
    Effects.enqueue(object, Effects.summon_creature(creature, [], nil))
  end

  def summon(%GameObject{} = object, _now), do: object
end
