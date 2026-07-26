defmodule ThistleTea.Game.Entity.Logic.Dueling do
  @moduledoc """
  Pure player-side duel projection and cleanup. The world duel system owns the
  pair; each character stores only the state needed by combat and update fields.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Duel
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Reactive

  def requested(%Character{internal: %Internal{} = internal, player: %Player{} = player} = character, %{
        initiator_guid: initiator_guid,
        opponent_guid: opponent_guid,
        arbiter_guid: arbiter_guid
      }) do
    duel = %Duel{
      initiator_guid: initiator_guid,
      opponent_guid: opponent_guid,
      arbiter_guid: arbiter_guid
    }

    %{
      character
      | internal: %{internal | duel: duel},
        player: %{player | duel_arbiter: arbiter_guid, duel_team: 0}
    }
    |> Core.mark_broadcast_update()
  end

  def requested(character, _payload), do: character

  def started(
        %Character{internal: %Internal{duel: %Duel{} = duel} = internal, player: %Player{} = player} = character,
        %{opponent_guid: opponent_guid, team: team, started_at: started_at}
      ) do
    duel = %{duel | opponent_guid: opponent_guid, state: :started, started_at: started_at}

    %{
      character
      | internal: %{internal | duel: duel, in_combat: true},
        player: %{player | duel_team: team}
    }
    |> Combat.sync_combat_flag()
    |> Core.mark_broadcast_update()
  end

  def started(character, _payload), do: character

  def finish(%Character{} = character, payload) when is_map(payload) do
    case character.internal.duel do
      %Duel{} = duel ->
        do_finish(character, duel, payload)

      nil ->
        {character, []}
    end
  end

  def abandon(%Character{} = character, now) when is_integer(now) do
    {character, events} = finish(character, %{now: now})
    Effects.enqueue(character, events)
  end

  def active?(%{internal: %Internal{duel: %Duel{state: :started}}}), do: true
  def active?(_entity), do: false

  def opponent_guid(%{internal: %Internal{duel: %Duel{opponent_guid: opponent_guid}}}), do: opponent_guid
  def opponent_guid(_entity), do: nil

  def lethal_source?(%{object: %{guid: victim_guid}, internal: %Internal{duel: %Duel{state: :started} = duel}}, opts)
      when is_list(opts) do
    source_guid = Keyword.get(opts, :source)
    source_owner_guid = Keyword.get(opts, :source_owner)
    reflected_by_guid = Keyword.get(opts, :reflected_by)

    duel.opponent_guid in [source_guid, source_owner_guid, reflected_by_guid] and
      (source_guid != victim_guid or reflected_by_guid == duel.opponent_guid)
  end

  def lethal_source?(_entity, _opts), do: false

  defp do_finish(character, duel, payload) do
    opponent_guid = Map.get(payload, :opponent_guid, duel.opponent_guid)
    opponent_pet_guid = Map.get(payload, :opponent_pet_guid)
    started_at = Map.get(payload, :started_at, duel.started_at)
    now = Map.fetch!(payload, :now)
    opponents = Enum.filter([opponent_guid, opponent_pet_guid], &is_integer/1)

    {character, modifier_events} =
      character
      |> remove_duel_auras(opponents, started_at, now)
      |> clear_duel_combat(opponents)

    {clear_projection(character), modifier_events}
  end

  defp remove_duel_auras(%Character{unit: %Unit{auras: holders}} = character, opponents, started_at, now)
       when is_list(holders) and is_integer(started_at) and is_integer(now) do
    kept =
      Enum.reject(holders, fn
        %Holder{negative?: true, caster_guid: caster_guid, applied_at: applied_at}
        when is_integer(applied_at) ->
          caster_guid in opponents and applied_at >= started_at

        _holder ->
          false
      end)

    Aura.transition(character, %Aura.Change{holders: kept, cause: :duel_end, now: now})
  end

  defp remove_duel_auras(character, _opponents, _started_at, _now), do: {character, []}

  defp clear_duel_combat({%Character{} = character, events}, opponents) do
    guid = character.object.guid
    target_guid = character.unit.target
    clear_target? = target_guid in opponents
    blackboard = Blackboard.ensure(character.internal.blackboard)

    blackboard =
      if blackboard.navigation.target in opponents do
        %{blackboard | navigation: %{blackboard.navigation | target: nil}}
      else
        blackboard
      end

    blackboard = Blackboard.clear_attack(blackboard)

    character =
      Enum.reduce(opponents, character, &Reactive.clear_combo_target(&2, &1))

    internal =
      if threat_refs?(character) do
        %{character.internal | duel: nil, blackboard: blackboard}
      else
        %{
          character.internal
          | duel: nil,
            blackboard: blackboard,
            in_combat: false,
            last_hostile_time: nil
        }
      end

    unit = if clear_target?, do: %{character.unit | target: 0}, else: character.unit
    character = %{character | internal: internal, unit: unit} |> Combat.sync_combat_flag()

    events =
      if clear_target? and is_integer(target_guid) and target_guid > 0 do
        events ++ [Effects.attack_stop(guid, target_guid)]
      else
        events
      end

    {character, events}
  end

  defp clear_projection(%Character{internal: %Internal{} = internal, player: %Player{} = player} = character) do
    %{
      character
      | internal: %{internal | duel: nil},
        player: %{player | duel_arbiter: 0, duel_team: 0}
    }
    |> Core.mark_broadcast_update()
  end

  defp threat_refs?(%Character{internal: %Internal{threat_refs: %MapSet{} = refs}}), do: MapSet.size(refs) > 0
  defp threat_refs?(_character), do: false
end
