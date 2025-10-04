defmodule ThistleTea.Game.GameObject.Data do
  alias ThistleTea.Game.FieldStruct

  defstruct object: %FieldStruct.Object{},
            game_object: %FieldStruct.GameObject{},
            movement_block: %FieldStruct.MovementBlock{},
            internal: %FieldStruct.Internal{}
end
