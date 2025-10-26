defmodule ThistleTea.Game.Message.SmsgCharEnum do
  use ThistleTea.Game.ServerMessage, :SMSG_CHAR_ENUM

  defmodule CharacterGear do
    defstruct [:equipment_display_id, :inventory_type]
  end

  defmodule Character do
    defstruct [
      :guid,
      :name,
      :race,
      :class,
      :gender,
      :skin,
      :face,
      :hair_style,
      :hair_color,
      :facial_hair,
      :level,
      :area,
      :map,
      :position,
      :guild_id,
      :flags,
      :first_login,
      :pet_display_id,
      :pet_level,
      :pet_family,
      :equipment,
      :first_bag_display_id,
      :first_bag_inventory_type
    ]
  end

  defstruct [:amount_of_characters, :characters]

  @impl ServerMessage
  def to_binary(%__MODULE__{amount_of_characters: amount, characters: characters}) do
    characters_binary =
      Enum.map(characters, fn char ->
        {x, y, z} = char.position

        equipment_binary =
          Enum.map(char.equipment, fn gear ->
            <<gear.equipment_display_id::little-size(32), gear.inventory_type::little-size(8)>>
          end)
          |> Enum.join()

        <<char.guid::little-size(64)>> <>
          char.name <>
          <<0>> <>
          <<char.race::little-size(8)>> <>
          <<char.class::little-size(8)>> <>
          <<char.gender::little-size(8)>> <>
          <<char.skin::little-size(8)>> <>
          <<char.face::little-size(8)>> <>
          <<char.hair_style::little-size(8)>> <>
          <<char.hair_color::little-size(8)>> <>
          <<char.facial_hair::little-size(8)>> <>
          <<char.level::little-size(8)>> <>
          <<char.area::little-size(32)>> <>
          <<char.map::little-size(32)>> <>
          <<x::little-float-size(32)>> <>
          <<y::little-float-size(32)>> <>
          <<z::little-float-size(32)>> <>
          <<char.guild_id::little-size(32)>> <>
          <<char.flags::little-size(32)>> <>
          <<char.first_login::little-size(8)>> <>
          <<char.pet_display_id::little-size(32)>> <>
          <<char.pet_level::little-size(32)>> <>
          <<char.pet_family::little-size(32)>> <>
          equipment_binary <>
          <<char.first_bag_display_id::little-size(32)>> <>
          <<char.first_bag_inventory_type::little-size(8)>>
      end)
      |> Enum.join()

    <<amount::little-size(8)>> <> characters_binary
  end
end
