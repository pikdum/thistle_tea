defmodule ThistleTea.Game.World.Loader.Gossip do
  @moduledoc """
  Loads gossip menus and options from Mangos into ETS, filtered to the option
  types the server supports, with creature-to-menu and trainer lookups.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  @option_gossip 1
  @option_vendor 3
  @option_taxi 4
  @option_trainer 5
  @option_spirit_healer 6
  @option_banker 9
  @supported_option_ids [
    @option_gossip,
    @option_vendor,
    @option_taxi,
    @option_trainer,
    @option_spirit_healer,
    @option_banker
  ]

  @npc_flag_trainer 0x10

  defmodule Menu do
    @moduledoc false
    defstruct [:menu_id, :text_id, texts: [], options: []]
  end

  defmodule Text do
    @moduledoc false
    defstruct [:text_id, :condition_id, :condition]
  end

  defmodule Option do
    @moduledoc false
    defstruct [:id, :icon, :text, :option_id, :action_menu_id, :condition, coded: 0, taxi_path_steps: []]
  end

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    menu_rows = Mangos.Repo.all(Mangos.GossipMenu)

    option_rows =
      from(o in Mangos.GossipMenuOption,
        where: o.option_id in ^@supported_option_ids
      )
      |> Mangos.Repo.all()

    taxi_steps_by_script =
      option_rows
      |> Enum.map(& &1.action_script_id)
      |> Enum.filter(&(&1 > 0))
      |> then(&Script.load_by_ids(Mangos.GossipScript, &1))
      |> Map.new(fn {script_id, steps} ->
        {script_id, Enum.filter(steps, &match?(%ScriptStep{command: :send_taxi_path}, &1))}
      end)

    option_rows =
      Enum.filter(option_rows, fn row ->
        row.condition_id == 0 or Map.get(taxi_steps_by_script, row.action_script_id, []) != []
      end)

    conditions =
      (option_rows ++ menu_rows)
      |> Enum.map(& &1.condition_id)
      |> ConditionLoader.load_by_ids()

    options_by_menu = Enum.group_by(option_rows, & &1.menu_id)

    menu_rows
    |> Enum.group_by(& &1.entry)
    |> Enum.each(fn {menu_id, rows} ->
      texts =
        rows
        |> Enum.sort_by(&{&1.condition_id, &1.text_id})
        |> Enum.map(fn row ->
          %Text{
            text_id: row.text_id,
            condition_id: row.condition_id,
            condition: Map.get(conditions, row.condition_id)
          }
        end)

      text_id =
        case Enum.find(texts, &(&1.condition_id == 0)) do
          %Text{text_id: text_id} -> text_id
          nil -> nil
        end

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
            condition: Map.get(conditions, o.condition_id),
            coded: o.box_coded,
            taxi_path_steps: Map.get(taxi_steps_by_script, o.action_script_id, [])
          }
        end)

      menu = %Menu{menu_id: menu_id, text_id: text_id, texts: texts, options: options}
      :ets.insert(__MODULE__, {{:menu, menu_id}, menu})
    end)

    from(ct in Mangos.CreatureTemplate,
      where: ct.gossip_menu_id > 0,
      select: {ct.entry, ct.gossip_menu_id}
    )
    |> Mangos.Repo.all()
    |> Enum.each(fn {creature_entry, menu_id} ->
      :ets.insert(__MODULE__, {{:creature_menu, creature_entry}, menu_id})
    end)

    from(ct in Mangos.CreatureTemplate,
      where: fragment("? & ?", ct.npc_flags, ^@npc_flag_trainer) != 0,
      select: {ct.entry, ct.trainer_type, ct.trainer_class, ct.trainer_race}
    )
    |> Mangos.Repo.all()
    |> Enum.each(fn {creature_entry, trainer_type, trainer_class, trainer_race} ->
      :ets.insert(
        __MODULE__,
        {{:trainer, creature_entry}, %{type: trainer_type, class: trainer_class, race: trainer_race}}
      )
    end)

    :ok
  end

  def trainer_of?(creature_entry, class, race, exalted? \\ false) do
    case :ets.lookup(__MODULE__, {:trainer, creature_entry}) do
      [{_key, %{type: 0, class: trainer_class}}] -> trainer_class == class
      [{_key, %{type: 1, race: trainer_race}}] -> trainer_race == race or exalted?
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
  def option_taxi, do: @option_taxi
  def option_trainer, do: @option_trainer
  def option_spirit_healer, do: @option_spirit_healer
  def option_banker, do: @option_banker
end
