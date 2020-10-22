defmodule Brolly do
  @moduledoc """
  Documentation for Brolly.
  """

  def dep_tree!(app, base_dir \\ ".") when is_atom(app) do
    Mix.Project.in_project(app, "#{base_dir}/#{app}", fn(_module) ->
      []
      |> Mix.Dep.load_on_environment()
      |> filter_dep_tree([])
      |> app_names([])
    end)
  end

  defp filter_dep_tree([], acc), do: acc

  defp filter_dep_tree([dep | tail], acc) do
    if brolly_dep?(dep) do
      dep = %{dep | deps: filter_dep_tree(dep.deps, [])}
      filter_dep_tree(tail, [dep | acc])
    else
      filter_dep_tree(tail, acc)
    end
  end

  defp app_names([], acc), do: acc

  defp app_names([%Mix.Dep{app: app, deps: []} | tail], acc) do
    app_names(tail, [app | acc])
  end

  defp app_names([%Mix.Dep{app: app, deps: deps} | tail], acc) do
    app_names(tail, [{app, app_names(deps, [])} | acc])
  end

  def reverse_dep_tree!(app, base_dir \\ ".", master \\ nil)
      when is_atom(app) and is_atom(master) do
    build_reverse_dep_tree(app, base_dir, master || config(base_dir).master)
  end

  defp build_reverse_dep_tree(app, base_dir, nil) do
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
      case build_reverse_dep_tree(dep, base_dir, nil) do
        [] -> dep
        deps -> {dep, deps}
      end
    end)
    |> Enum.to_list()
  end

  defp build_reverse_dep_tree(app, base_dir, master) do
    Mix.Project.in_project(master, "#{base_dir}/#{master}", fn(_module) ->
      deps =
        []
        |> Mix.Dep.load_on_environment()
        |> filter_dep_tree([])

        reversed_app_names(deps, app, deps, [])
    end)
  end

  defp reversed_app_names([], _, _, acc), do: acc

  defp reversed_app_names([dep | tail], app, all_deps, acc) do
    if depends_from?(dep, app) do
      dep = case reversed_app_names(all_deps, dep.app, all_deps, []) do
        [] -> dep.app
        deps -> {dep.app, deps}
      end
      reversed_app_names(tail, app, all_deps, [dep | acc])
    else
      reversed_app_names(tail, app, all_deps, acc)
    end
  end

  defp depends_from?(left, right, base_dir \\ ".")

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

  defp brolly_dep?(%Mix.Dep{app: name, scm: Mix.SCM.Path, opts: opts}) do
    opts[:path] == "../#{name}"
  end

  defp brolly_dep?(%Mix.Dep{}), do: false

  @default_config %{master: nil}

  def config(base_dir \\ ".") do
    base_dir
    |> load_config_file()
    |> Enum.into(@default_config)
  end

  defp load_config_file(base_dir) do
    with file = Path.join(base_dir, ".brolly_config.exs"),
         {:ok, content} <- File.read(file),
         {config, _} <- Code.eval_string(content) do
      config
    else
      _ -> %{}
    end
  end

  def affected_projects(sha, base_dir \\ ".", git_root \\ :base_dir, master \\ nil) do
    sha
    |> changed_projects(base_dir, git_root)
    |> Stream.map(&reverse_dep_tree!(&1, base_dir, master))
    |> Enum.uniq()
  end

  defp flatten_tree([], acc), do: acc

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
