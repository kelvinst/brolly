defmodule Brolly do
  @moduledoc """
  Documentation for Brolly.
  """

  def dep_tree!(app \\ nil, base_dir \\ ".")

  def dep_tree!(nil, base_dir) do
    base_dir
    |> Path.join("apps")
    |> File.ls!()
    |> Stream.map(&Path.basename/1)
    |> Stream.map(&String.to_atom/1)
    |> Enum.map(&{&1, dep_tree!(&1, base_dir)})
  end

  def dep_tree!(app, base_dir) when is_atom(app) do
    Mix.Project.in_project(app, "#{base_dir}/apps/#{app}", fn(_module) ->
      []
      |> Mix.Dep.load_on_environment()
      |> filter_dep_tree(app, [])
      |> app_names([])
    end)
  end

  defp filter_dep_tree([], _, acc), do: acc

  defp filter_dep_tree([dep | tail], app, acc) do
    if umbrella_dep?(dep, app) do
      dep = %{dep | deps: filter_dep_tree(dep.deps, dep.app, [])}
      filter_dep_tree(tail, app, [dep | acc])
    else
      filter_dep_tree(tail, app, acc)
    end
  end

  defp app_names([], acc), do: acc

  defp app_names([%Mix.Dep{app: app, deps: []} | tail], acc) do
    app_names(tail, [app | acc])
  end

  defp app_names([%Mix.Dep{app: app, deps: deps} | tail], acc) do
    app_names(tail, [{app, app_names(deps, [])} | acc])
  end

  def reverse_dep_tree!(app, base_dir \\ ".") when is_atom(app) do
    # TODO - this is very slow for big project, since we need to go
    # through all directories and load each project. Unfortunately, there is no
    # other way to do it with the current version of mix, other than rewriting
    # the deps load.
    base_dir
    |> File.ls!()
    |> Stream.filter(&File.dir?(Path.join(base_dir, &1)))
    |> Stream.map(&String.to_atom/1)
    |> Stream.filter(&depends_from?(&1, app, base_dir))
    |> Stream.map(fn(dep) ->
      case reverse_dep_tree!(dep, base_dir) do
        [] -> dep
        deps -> {dep, deps}
      end
    end)
    |> Enum.to_list()
  end

  defp depends_from?(%Mix.Dep{deps: left_deps}, right, _) do
    Enum.any?(left_deps, &(&1.app == right))
  end

  defp depends_from?(left, right, base_dir) when is_atom(left) and is_atom(right) do
    Mix.Project.in_project(left, "#{base_dir}/#{left}", fn(_module) ->
      []
      |> Mix.Dep.load_on_environment()
      |> Enum.any?(&(&1.app == right))
    end)
  end

  defp umbrella_dep?(%Mix.Dep{scm: Mix.SCM.Path, opts: opts, from: from}, app) do
    opts[:in_umbrella] && from == Path.expand("../#{app}/mix.exs")
  end

  defp umbrella_dep?(%Mix.Dep{}, _), do: false

  def affected_projects(sha, base_dir \\ ".", git_root \\ :base_dir) do
    sha
    |> changed_projects(base_dir, git_root)
    |> Stream.map(&reverse_dep_tree!(&1, base_dir))
    |> Enum.uniq()
  end

  def changed_projects(sha, base_dir \\ ".", git_root \\ :base_dir) do
    base_dir
    |> Git.new()
    |> Git.diff_tree!(["--no-commit-id", "--name-only", "-r", sha])
    |> String.split("\n")
    |> handle_git_root(base_dir, git_root)
    |> Stream.map(&List.first(String.split(&1, "/")))
    |> Stream.map(&String.slice(&1, 0, String.length(&1)))
    |> Stream.filter(&File.dir?(Path.join(base_dir, &1)))
    |> Stream.map(&String.to_atom/1)
    |> Enum.uniq()
  end

  defp handle_git_root(lines, _base_dir, :base_dir), do: lines

  defp handle_git_root(lines, base_dir, git_root) do
    subdir = String.replace(Path.expand(base_dir), Path.expand(git_root) <> "/", "")

    lines
    |> Stream.filter(&String.starts_with?(&1, "#{subdir}/"))
    |> Stream.map(&String.replace(&1, "#{subdir}/", ""))
  end
end
