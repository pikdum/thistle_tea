defmodule ThistleTea.Game.Entity.Logic.Silithyst do
  @moduledoc "Pure Silithyst pickup, carrier removal, and faction turn-in transitions."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  @carrier 29_519
  @favor 30_754
  @team_auras [29_894, 29_895]

  def carrier_spell, do: @carrier
  def favor_spell, do: @favor
  def objective_zone?(1377), do: true
  def objective_zone?(_zone), do: false
  def buff_zone?(zone), do: zone in [1377, 3428, 3429]
  def trigger?(:alliance, 4162), do: true
  def trigger?(:horde, 4168), do: true
  def trigger?(_team, _trigger), do: false
  def credit_entry(:alliance), do: 17_090
  def credit_entry(:horde), do: 18_199

  def blocks_object?(%Character{} = character, %GameObjectTemplate{entry: entry}) when entry in [181_597, 181_598],
    do: Aura.has_spell?(character, @carrier)

  def blocks_object?(_character, _template), do: false

  def reconcile(holders) do
    if Enum.any?(holders, &(&1.spell.id == @carrier)),
      do: holders,
      else: Enum.reject(holders, &(&1.spell.id in @team_auras))
  end

  def after_apply(%Character{} = character, holders) do
    if Enum.any?(holders, &(&1.spell.id == @carrier)) do
      case Battleground.team_for_race(character.unit.race) do
        :alliance -> [self_spell(character, 29_894)]
        :horde -> [self_spell(character, 29_895)]
        _ -> []
      end
    else
      []
    end
  end

  def after_apply(_entity, _holders), do: []

  def pickup(%Character{} = character, now) do
    if Death.alive?(character) and not Aura.has_spell?(character, @carrier) do
      {Pvp.contest(character, now), [self_spell(character, @carrier)]}
    else
      {character, []}
    end
  end

  def pickup(entity, _now), do: {entity, []}

  def refresh_pvp(%Character{} = character, now) do
    if Aura.has_spell?(character, @carrier), do: Pvp.contest(character, now), else: character
  end

  def refresh_pvp(entity, _now), do: entity

  def turn_in(%Character{internal: %{world: %WorldRef{map_id: 1, instance_id: nil}}} = character, trigger, now) do
    team = Battleground.team_for_race(character.unit.race)

    with true <- Death.alive?(character) and trigger?(team, trigger),
         %Holder{} = holder <- Enum.find(character.unit.auras || [], &(&1.spell.id == @carrier)) do
      holders = Enum.reject(character.unit.auras, &(&1.spell.id == @carrier))
      change = %Change{holders: holders, cause: :consumed, now: now}
      {character, events} = Transition.run(character, change)
      token = {holder.caster_guid, holder.applied_at}
      rewards = Enum.map([29_534, 31_420, 31_247], &self_spell(character, &1))
      {:ok, character, team, token, events ++ rewards}
    else
      _ -> :unavailable
    end
  end

  def turn_in(_entity, _trigger, _now), do: :unavailable

  def after_remove(%Character{} = character, %Holder{spell: %Spell{id: @carrier}}, cause) do
    if cause == :consumed or Aura.has_spell?(character, @carrier) do
      []
    else
      [Effects.summon_game_object(181_597, 180_000, owned?: false, position: character.movement_block.position)]
    end
  end

  def after_remove(_entity, _holder, _cause), do: []

  defp self_spell(character, id) do
    Effects.trigger_spell(character.object.guid, character.unit.level || 1, character.object.guid, id)
  end
end
