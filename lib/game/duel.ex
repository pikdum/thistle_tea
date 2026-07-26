defmodule ThistleTea.Game.Duel do
  @moduledoc """
  Pure duel lifecycle: challenge admission, countdown/start transitions, and
  hysteresis-backed boundary tracking around the duel flag.
  """

  defmodule Match do
    @moduledoc false

    defstruct [
      :id,
      :initiator_guid,
      :opponent_guid,
      :arbiter_guid,
      :world,
      :flag_position,
      :countdown_started_at,
      :started_at,
      state: :requested,
      out_of_bounds: %{}
    ]
  end

  defmodule Admission do
    @moduledoc false

    @enforce_keys [
      :initiator_guid,
      :opponent_guid,
      :initiator_player?,
      :opponent_player?,
      :initiator_online?,
      :opponent_online?,
      :initiator_allowed?,
      :opponent_allowed?,
      :same_world?,
      :initiator_busy?,
      :opponent_busy?
    ]
    defstruct [
      :initiator_guid,
      :opponent_guid,
      :initiator_player?,
      :opponent_player?,
      :initiator_online?,
      :opponent_online?,
      :initiator_allowed?,
      :opponent_allowed?,
      :same_world?,
      :initiator_busy?,
      :opponent_busy?
    ]
  end

  @outbound_radius 75.0
  @inbound_radius 70.0
  @forfeit_delay_ms 10_000

  defstruct next_id: 1, matches: %{}, player_matches: %{}

  def challenge(%__MODULE__{} = duels, %Admission{} = admission, attrs) when is_map(attrs) do
    with :ok <- validate_admission(admission) do
      cond do
        busy?(duels, admission.initiator_guid) -> {:error, :initiator_busy}
        busy?(duels, admission.opponent_guid) -> {:error, :opponent_busy}
        true -> add_match(duels, admission.initiator_guid, admission.opponent_guid, attrs)
      end
    end
  end

  def challenge(%__MODULE__{}, _admission, _attrs), do: {:error, :invalid_players}

  def validate_admission(%Admission{initiator_guid: initiator_guid, opponent_guid: opponent_guid})
      when not is_integer(initiator_guid) or not is_integer(opponent_guid) or initiator_guid == opponent_guid,
      do: {:error, :invalid_players}

  def validate_admission(%Admission{initiator_player?: false}), do: {:error, :invalid_players}
  def validate_admission(%Admission{opponent_player?: false}), do: {:error, :invalid_players}
  def validate_admission(%Admission{initiator_online?: false}), do: {:error, :not_online}
  def validate_admission(%Admission{opponent_online?: false}), do: {:error, :not_online}
  def validate_admission(%Admission{initiator_allowed?: false}), do: {:error, :no_dueling}
  def validate_admission(%Admission{opponent_allowed?: false}), do: {:error, :no_dueling}
  def validate_admission(%Admission{same_world?: false}), do: {:error, :invalid_world}
  def validate_admission(%Admission{initiator_busy?: true}), do: {:error, :initiator_busy}
  def validate_admission(%Admission{opponent_busy?: true}), do: {:error, :opponent_busy}

  def validate_admission(%Admission{
        initiator_player?: true,
        opponent_player?: true,
        initiator_online?: true,
        opponent_online?: true,
        initiator_allowed?: true,
        opponent_allowed?: true,
        same_world?: true,
        initiator_busy?: false,
        opponent_busy?: false
      }), do: :ok

  def validate_admission(_admission), do: {:error, :invalid_players}

  def accept(%__MODULE__{} = duels, opponent_guid, now) when is_integer(opponent_guid) and is_integer(now) do
    case match_for(duels, opponent_guid) do
      %Match{opponent_guid: ^opponent_guid, state: :requested} = match ->
        match = %{match | state: :countdown, countdown_started_at: now}
        {:ok, match, put_match(duels, match)}

      %Match{} ->
        {:error, :not_opponent}

      nil ->
        {:error, :not_found}
    end
  end

  def accept(%__MODULE__{}, _opponent_guid, _now), do: {:error, :invalid_accept}

  def start(%__MODULE__{} = duels, match_id, now) when is_integer(match_id) and is_integer(now) do
    case Map.get(duels.matches, match_id) do
      %Match{state: :countdown} = match ->
        match = %{match | state: :started, countdown_started_at: nil, started_at: now}
        {:ok, match, put_match(duels, match)}

      %Match{} ->
        {:error, :not_counting_down}

      nil ->
        {:error, :not_found}
    end
  end

  def start(%__MODULE__{}, _match_id, _now), do: {:error, :invalid_start}

  def complete(%__MODULE__{} = duels, guid) when is_integer(guid) do
    case match_for(duels, guid) do
      %Match{} = match -> {:ok, match, delete_match(duels, match)}
      nil -> {:error, :not_found}
    end
  end

  def complete(%__MODULE__{}, _guid), do: {:error, :not_found}

  def check_bounds(%__MODULE__{} = duels, match_id, distances, now)
      when is_integer(match_id) and is_map(distances) and is_integer(now) do
    case Map.get(duels.matches, match_id) do
      %Match{state: :started} = match ->
        case bound_transitions(match, distances, now) do
          {:fled, loser_guid} ->
            {[{:fled, loser_guid, opponent(match, loser_guid)}], duels}

          {events, match} ->
            {events, put_match(duels, match)}
        end

      _not_started ->
        {[], duels}
    end
  end

  def check_bounds(%__MODULE__{} = duels, _match_id, _distances, _now), do: {[], duels}

  def match_for(%__MODULE__{} = duels, guid) when is_integer(guid) do
    case Map.get(duels.player_matches, guid) do
      id when is_integer(id) -> Map.get(duels.matches, id)
      _ -> nil
    end
  end

  def match_for(%__MODULE__{}, _guid), do: nil

  def busy?(%__MODULE__{} = duels, guid), do: not is_nil(match_for(duels, guid))

  def opponent(%Match{initiator_guid: guid, opponent_guid: opponent_guid}, guid), do: opponent_guid
  def opponent(%Match{initiator_guid: initiator_guid, opponent_guid: guid}, guid), do: initiator_guid
  def opponent(%Match{}, _guid), do: nil

  def participants(%Match{} = match), do: [match.initiator_guid, match.opponent_guid]

  defp add_match(duels, initiator_guid, opponent_guid, attrs) do
    match = %Match{
      id: duels.next_id,
      initiator_guid: initiator_guid,
      opponent_guid: opponent_guid,
      arbiter_guid: Map.get(attrs, :arbiter_guid),
      world: Map.get(attrs, :world),
      flag_position: Map.get(attrs, :flag_position)
    }

    player_matches =
      duels.player_matches
      |> Map.put(initiator_guid, match.id)
      |> Map.put(opponent_guid, match.id)

    duels = %{
      duels
      | next_id: duels.next_id + 1,
        matches: Map.put(duels.matches, match.id, match),
        player_matches: player_matches
    }

    {:ok, match, duels}
  end

  defp put_match(%__MODULE__{} = duels, %Match{} = match) do
    %{duels | matches: Map.put(duels.matches, match.id, match)}
  end

  defp delete_match(%__MODULE__{} = duels, %Match{} = match) do
    player_matches =
      duels.player_matches
      |> Map.drop([match.initiator_guid, match.opponent_guid])

    %{duels | matches: Map.delete(duels.matches, match.id), player_matches: player_matches}
  end

  defp bound_transitions(%Match{} = match, distances, now) do
    Enum.reduce_while(participants(match), {[], match}, fn guid, {events, match} ->
      distance = Map.get(distances, guid)
      since = Map.get(match.out_of_bounds, guid)
      bound_transition(match, events, guid, distance, since, now)
    end)
  end

  defp bound_transition(_match, _events, guid, distance, _since, _now) when not is_number(distance) do
    {:halt, {:fled, guid}}
  end

  defp bound_transition(match, events, guid, distance, nil, now) when distance > @outbound_radius do
    match = %{match | out_of_bounds: Map.put(match.out_of_bounds, guid, now)}
    {:cont, {events ++ [{:out_of_bounds, guid}], match}}
  end

  defp bound_transition(_match, _events, guid, distance, since, now)
       when is_integer(since) and distance > @inbound_radius and now - since >= @forfeit_delay_ms do
    {:halt, {:fled, guid}}
  end

  defp bound_transition(match, events, guid, distance, since, _now)
       when is_integer(since) and distance <= @inbound_radius do
    match = %{match | out_of_bounds: Map.delete(match.out_of_bounds, guid)}
    {:cont, {events ++ [{:in_bounds, guid}], match}}
  end

  defp bound_transition(match, events, _guid, _distance, _since, _now), do: {:cont, {events, match}}
end
