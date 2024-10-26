defmodule ThistleTeaWeb.MapLive.Index do
  # use ThistleTeaWeb, :live_view
  use Phoenix.LiveView, container: {:div, class: "h-full w-full"}

  alias ThistleTeaWeb.Homography

  require Logger

  @update_interval 1_000

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="relative h-full w-full cursor-grab bg-stone-200 active:cursor-grabbing"
      id="map-wrapper"
    >
      <div class="h-full w-full" id="map" phx-hook="Map" phx-update="ignore" />
      <%= if @map_ready do %>
        <div class="absolute top-2 right-2 cursor-text rounded-md bg-black p-2 px-4 text-white opacity-80">
          Online: <%= length(assigns.entities) %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(entities: []) |> assign(map_ready: false), layout: false}
  end

  @impl true
  def handle_event("map_ready", true, %{assigns: %{map_ready: false}} = socket) do
    :timer.send_interval(@update_interval, self(), :update_entities)
    handle_info(:update_entities, socket |> assign(map_ready: true))
  end

  @impl true
  def handle_event("map_ready", _, socket) do
    handle_info(:update_entities, socket)
  end

  @impl true
  def handle_info(:update_entities, socket) do
    current_entities = socket.assigns.entities
    new_entities = fetch_entities()

    {added, updated, removed} = diff_entities(current_entities, new_entities)

    if added != [] or updated != [] or removed != [] do
      {:noreply,
       socket
       |> push_event("entity_updates", %{
         added: added,
         updated: updated,
         removed: removed
       })
       |> assign(entities: new_entities)}
    else
      {:noreply, assign(socket, entities: new_entities)}
    end
  end

  defp fetch_entities do
    :ets.tab2list(:entities)
    |> Enum.filter(fn {guid, _pid, map, _x, _y, _z} ->
      # anything under is a player
      map <= 1 and guid < 0x1FC00000
    end)
    |> Enum.map(fn {guid, _pid, map, x, y, _z} ->
      [{^guid, name, _realm, _race, _gender, _class}] = :ets.lookup(:guid_name, guid)

      {x, y} = Homography.transform({x, y}, map)

      %{
        name: name,
        guid: guid,
        map: map,
        x: x,
        y: y
      }
    end)
  end

  # TODO: should i rework to use MapSet?
  defp diff_entities(old_entities, new_entities) do
    old_map = Map.new(old_entities, &{&1.guid, &1})
    new_map = Map.new(new_entities, &{&1.guid, &1})

    added = Enum.filter(new_entities, &(!Map.has_key?(old_map, &1.guid)))

    updated =
      Enum.filter(new_entities, fn entity ->
        case Map.get(old_map, entity.guid) do
          nil -> false
          old_entity -> entity != old_entity
        end
      end)

    removed = Enum.filter(old_entities, &(!Map.has_key?(new_map, &1.guid)))

    {added, updated, removed}
  end
end
