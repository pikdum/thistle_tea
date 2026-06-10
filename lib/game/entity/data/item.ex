defmodule ThistleTea.Game.Entity.Data.Item do
  alias ThistleTea.Game.Entity.Data.Component.Item, as: ItemComponent
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  defstruct object: %Object{},
            item: %ItemComponent{},
            internal: %{template: nil}

  def build(%ItemTemplate{} = template, guid, opts \\ []) do
    owner = Keyword.get(opts, :owner, 0)
    stack_count = Keyword.get(opts, :stack_count, 1)

    %__MODULE__{
      object: %Object{
        guid: guid,
        entry: template.entry,
        scale_x: 1.0
      },
      item: %ItemComponent{
        owner: owner,
        contained: owner,
        stack_count: stack_count,
        duration: template.duration,
        flags: template.flags,
        durability: template.max_durability,
        max_durability: template.max_durability
      },
      internal: %{template: template}
    }
  end

  def template(%__MODULE__{internal: %{template: template}}), do: template
end
