defmodule ThistleTeaWeb.MapLive.Index do
  use ThistleTeaWeb, :live_view

  require Logger

  def render(assigns) do
    ~H"""
    <div class="w-screen h-screen" id="map" phx-hook="Map" phx-update="ignore" data-entities={Jason.encode!(@entities)}></div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    entities =
      :ets.tab2list(:entities)
      |> Enum.filter(fn {guid, _pid, map, x, y, _z} ->
        # anything under is a player
        map == 0 and guid < 0x1FC00000
      end)
      |> Enum.map(fn {guid, _pid, map, x, y, z} ->
        %{
          guid: guid,
          map: map,
          x: x,
          y: y,
          z: z
        }
      end)

    {:ok, socket |> assign(entities: entities), layout: false}
  end
end
