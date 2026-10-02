defmodule ThistleTea.Game.Core.Creature.GuardCall do
  @moduledoc """
  Civilians that call the guards on enemy players, after vmangos `BasicAI`.

  A creature with the calls-guards static flag that cannot attack on sight
  watches its detection range for enemy players, and any such creature calls
  the guards when it enters combat. While fighting it watches only its
  victim. A civilian makes one call at a time. The request stays pending
  until the boundary answers it; a denied call leaves the civilian ready for
  its next sighting, and a summoned guard keeps it quiet until that guard
  dies or leaves. Any other answer, such as rousing a nearby guard, holds
  until it respawns. A pending call keeps the watch range, so a denial never
  changes what the civilian announces and cannot probe it straight again.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Detection
  alias ThistleTea.Game.Core.Combat.Aggro
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent

  @calls_guards 0x08000000
  @vertical_range 3.0
  @summon_endings [:summoned_just_died, :summoned_just_despawn]

  def caller?(%Mob{internal: %Internal{pet: nil, totem: nil, creature: %Creature{static_flags: flags}}})
      when is_integer(flags), do: (flags &&& @calls_guards) != 0

  def caller?(_entity), do: false

  def ready?(%Mob{unit: %Unit{charmed_by: charmer}, internal: %Internal{creature: %Creature{guard_call: nil}}} = mob)
      when charmer in [nil, 0], do: caller?(mob) and not Entity.dead?(mob)

  def ready?(_entity), do: false

  def watch_range(%Mob{internal: %Internal{in_combat: in_combat, blackboard: blackboard}} = mob) do
    if on_watch?(mob) and not evading?(blackboard) and (in_combat == true or not Mob.proximity_aggro?(mob)),
      do: Aggro.detection_range(mob)
  end

  def watch_range(_entity), do: nil

  def sees?(%Mob{} = mob, enemy_guid, %Context{perception: perception} = context) when is_integer(enemy_guid) do
    range = watch_range(mob)
    distance = Perception.distance(perception, enemy_guid)

    is_number(range) and is_number(distance) and distance <= range and Guid.entity_type(enemy_guid) == :player and
      watching?(mob, enemy_guid) and
      Hostility.valid_hostile_target?(
        Perception.actor(perception, mob.object.guid),
        Perception.actor(perception, enemy_guid)
      ) and
      level?(mob, Perception.position(perception, enemy_guid)) and
      Detection.detectable?(mob, enemy_guid, context) and
      Perception.line_of_sight?(perception, enemy_guid)
  end

  def sees?(_entity, _enemy_guid, _context), do: false

  def request(%Mob{} = mob, enemy_guid) when is_integer(enemy_guid) and enemy_guid > 0 do
    if ready?(mob),
      do: mob |> put(:pending) |> Effects.enqueue(Effects.call_guards(enemy_guid)),
      else: mob
  end

  def request(entity, _enemy_guid), do: entity

  def on_enter_combat(%Mob{} = mob, enemy_guid), do: if(caller?(mob), do: request(mob, enemy_guid), else: mob)

  def answered(%Mob{internal: %Internal{creature: %Creature{guard_call: :pending}}} = mob, {:summoned, entry})
      when is_integer(entry), do: put(mob, {:summoned, entry})

  def answered(%Mob{internal: %Internal{creature: %Creature{guard_call: :pending}}} = mob, :held), do: put(mob, :held)

  def answered(%Mob{internal: %Internal{creature: %Creature{guard_call: :pending}}} = mob, :denied), do: put(mob, nil)
  def answered(entity, _answer), do: entity

  def summon_ended(%Mob{internal: %Internal{creature: %Creature{guard_call: {:summoned, entry}}}} = mob, %SummonEvent{
        event: event,
        entry: entry
      })
      when event in @summon_endings, do: put(mob, nil)

  def summon_ended(entity, _event), do: entity

  def reset(%Mob{internal: %Internal{creature: %Creature{guard_call: nil}}} = mob), do: mob
  def reset(%Mob{internal: %Internal{creature: %Creature{}}} = mob), do: put(mob, nil)
  def reset(entity), do: entity

  defp put(%Mob{internal: %Internal{creature: %Creature{} = creature} = internal} = mob, guard_call),
    do: %{mob | internal: %{internal | creature: %{creature | guard_call: guard_call}}}

  defp on_watch?(
         %Mob{unit: %Unit{charmed_by: charmer}, internal: %Internal{creature: %Creature{guard_call: guard_call}}} = mob
       )
       when charmer in [nil, 0] and guard_call in [nil, :pending], do: caller?(mob) and not Entity.dead?(mob)

  defp on_watch?(_entity), do: false

  defp watching?(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: victim}}, enemy_guid),
    do: victim == enemy_guid

  defp watching?(_mob, _enemy_guid), do: true

  defp level?(%Mob{movement_block: %{position: {_x, _y, z, _orientation}}}, {_world, _tx, _ty, target_z}),
    do: abs(target_z - z) <= @vertical_range

  defp level?(_mob, _position), do: false

  defp evading?(%Blackboard{navigation: %{returning_home?: true}}), do: true
  defp evading?(_blackboard), do: false
end
