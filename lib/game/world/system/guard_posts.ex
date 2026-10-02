defmodule ThistleTea.Game.World.System.GuardPosts do
  @moduledoc """
  Owns the charges of every town guard post, so civilians across a town
  share one post's cooldown the way vmangos `GuardMgr` does. A post is
  created the first time its area calls for a guard.
  """

  use GenServer

  alias ThistleTea.Game.Core.Creature.GuardPost
  alias ThistleTea.Game.Core.Time

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def take(area_id, now \\ Time.now(), server \\ __MODULE__) when is_integer(area_id) and is_integer(now) do
    GenServer.call(server, {:take, area_id, now})
  catch
    :exit, reason ->
      Logger.warning("Guard post #{area_id} unavailable: #{inspect(reason)}")
      :denied
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:take, area_id, now}, _from, posts) do
    {result, post} = posts |> Map.get(area_id, %GuardPost{}) |> GuardPost.take(now)
    {:reply, result, Map.put(posts, area_id, post)}
  end
end
