defmodule BrollyTest do
  use ExUnit.Case
  doctest Brolly

  test "greets the world" do
    assert Brolly.hello() == :world
  end
end
