defmodule PonchoTest do
  use ExUnit.Case
  doctest Poncho

  test "greets the world" do
    assert Poncho.hello() == :world
  end
end
