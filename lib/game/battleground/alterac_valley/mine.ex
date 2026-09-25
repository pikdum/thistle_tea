defmodule ThistleTea.Game.Battleground.AlteracValley.Mine do
  @moduledoc "Mine ownership, faction supply access, and revision-checked neutral reclamation."

  @enforce_keys [:id]
  defstruct [:id, :owner, :reclaim_at, revision: 0]

  @reclaim_ms 1_200_000

  def all, do: Map.new(0..1, &{&1, %__MODULE__{id: &1}})
  def reclaim_ms, do: @reclaim_ms

  def capture(%__MODULE__{owner: team} = mine, team, _now), do: {:unchanged, mine}

  def capture(%__MODULE__{} = mine, team, now) when team in [:alliance, :horde] and is_integer(now) do
    {:captured, %{mine | owner: team, reclaim_at: now + @reclaim_ms, revision: mine.revision + 1}}
  end

  def reclaim(%__MODULE__{revision: revision, reclaim_at: deadline} = mine, revision, now)
      when is_integer(deadline) and now >= deadline do
    {:reclaimed, %{mine | owner: nil, reclaim_at: nil, revision: revision + 1}}
  end

  def reclaim(%__MODULE__{} = mine, _revision, _now), do: {:unchanged, mine}

  def event_state(%__MODULE__{owner: :alliance}), do: 0
  def event_state(%__MODULE__{owner: :horde}), do: 1
  def event_state(%__MODULE__{}), do: 2

  def events(%__MODULE__{id: id} = mine), do: [{46 + id, event_state(mine)}, {50 + id, event_state(mine)}]

  def supply_mine_id(entry) when entry in [178_785, 178_788, 178_789], do: 0
  def supply_mine_id(entry) when entry in [178_784, 178_786, 178_787], do: 1
  def supply_mine_id(_entry), do: nil

  def supply_allowed?(%__MODULE__{owner: team}, team) when team in [:alliance, :horde], do: true
  def supply_allowed?(%__MODULE__{}, _team), do: false

  def world_states(%__MODULE__{id: id} = mine) do
    first_field = if id == 0, do: 1_358, else: 1_355
    for state <- 0..2, do: {first_field + state, if(event_state(mine) == state, do: 1, else: 0)}
  end
end
