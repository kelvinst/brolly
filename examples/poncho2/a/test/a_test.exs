defmodule ATest do
  use ExUnit.Case
  doctest A

  test "greets the world" do
    assert A.hello() == :world
  end
end
