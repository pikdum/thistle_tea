defmodule ThistleTea.Game.World.Loader.Gossip do
  @moduledoc """
  Loads gossip menus and options from Mangos into ETS, filtered to the option
  types the server supports, with creature-to-menu and trainer lookups.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  @option_gossip 1
  @option_vendor 3
  @option_trainer 5
  @option_spirit_healer 6
  @supported_option_ids [@option_gossip, @option_vendor, @option_trainer, @option_spirit_healer]

  defmodule Menu do
    @moduledoc false
    defstruct [:menu_id, :text_id, options: []]
  end

  defmodule Option do
    @moduledoc false
    defstruct [:id, :icon, :text, :option_id, :action_menu_id, coded: 0]
  end

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    options_by_menu =
      from(o in Mangos.GossipMenuOption,
        where: o.condition_id == 0 and o.option_id in ^@supported_option_ids
      )
      |> Mangos.Repo.all()
      |> Enum.group_by(& &1.menu_id)

    Mangos.GossipMenu
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
    |> Enum.each(fn {menu_id, rows} ->
      row = Enum.min_by(rows, fn row -> {row.condition_id, row.text_id} end)

      options =
        options_by_menu
        |> Map.get(menu_id, [])
        |> Enum.sort_by(& &1.id)
        |> Enum.map(fn o ->
          %Option{
            id: o.id,
            icon: o.option_icon,
            text: o.option_text,
            option_id: o.option_id,
            action_menu_id: o.action_menu_id,
            coded: o.box_coded
          }
        end)

      menu = %Menu{menu_id: menu_id, text_id: row.text_id, options: options}
      :ets.insert(__MODULE__, {{:menu, menu_id}, menu})
    end)

    from(ct in Mangos.CreatureTemplate,
      where: ct.gossip_menu_id > 0,
      select: {ct.entry, ct.gossip_menu_id, ct.trainer_type, ct.trainer_class, ct.trainer_race}
    )
    |> Mangos.Repo.all()
    |> Enum.each(fn {creature_entry, menu_id, trainer_type, trainer_class, trainer_race} ->
      :ets.insert(__MODULE__, {{:creature_menu, creature_entry}, menu_id})

      :ets.insert(
        __MODULE__,
        {{:trainer, creature_entry}, %{type: trainer_type, class: trainer_class, race: trainer_race}}
      )
    end)

    :ok
  end

  def trainer_of?(creature_entry, class, race) do
    case :ets.lookup(__MODULE__, {:trainer, creature_entry}) do
      [{_key, %{type: 0, class: trainer_class}}] -> trainer_class == class
      [{_key, %{type: 1, race: trainer_race}}] -> trainer_race == race
      [{_key, %{}}] -> true
      _ -> false
    end
  end

  def get_menu(menu_id) do
    case :ets.lookup(__MODULE__, {:menu, menu_id}) do
      [{_key, %Menu{} = menu}] -> menu
      _ -> nil
    end
  end

  def menu_for_creature(creature_entry) do
    case :ets.lookup(__MODULE__, {:creature_menu, creature_entry}) do
      [{_key, menu_id}] -> get_menu(menu_id)
      _ -> nil
    end
  end

  def option_vendor, do: @option_vendor
  def option_gossip, do: @option_gossip
  def option_trainer, do: @option_trainer
  def option_spirit_healer, do: @option_spirit_healer
end
