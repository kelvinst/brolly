defmodule Mix.Tasks.Brolly.Tree do
  use Mix.Task

  @shortdoc "Prints the dependency tree for the brolly project"

  @switches [base_dir: :string, reverse: :boolean, master: :string, format: :string]
  @aliases [b: :base_dir, r: :reverse, m: :master, f: :format]

  @default_opts [base_dir: ".", reverse: false, master: "nil", format: "plain"]
  @plain_indent 4

  def run(args) do
    {opts, args, _} = OptionParser.parse(args, aliases: @aliases, switches: @switches)
    opts = Keyword.merge(@default_opts, opts)

    project = case args do
      [] -> master(opts) || Brolly.config(opts[:base_dir]).master
      [project_name] -> String.to_atom(project_name)
    end

    dep_tree = dep_tree(project, opts)
    case opts[:format] do
      "plain" ->
        formatted_deps = plain_format_deps(dep_tree, @plain_indent, [])

        [project | formatted_deps]
        |> Enum.join("\n")
        |> Mix.shell().info()

      "dot" ->
        formatted_deps = dot_format_deps(dep_tree, nil, [])

        content =
          [~s(digraph "dependency tree" {), formatted_deps, "}"]
          |> List.flatten()
          |> Enum.join("\n")

        File.write!("brolly_tree.dot", content)

        """
        Generated "brolly_tree.dot" in the current directory.

        To generate a PNG:

            dot -Tpng brolly_tree.dot -o brolly_tree.png

        For more options see http://www.graphviz.org/.
        """
        |> String.trim_trailing()
        |> Mix.shell().info()
    end
  end

  defp dep_tree(app, opts), do: dep_tree(app, opts[:reverse], opts[:base_dir], master(opts))

  defp dep_tree(app, true, base_dir, master), do: Brolly.reverse_dep_tree!(app, base_dir, master)
  defp dep_tree(app, false, base_dir, _), do: Brolly.dep_tree!(app, base_dir)

  defp master(opts), do: String.to_atom(opts[:master])

  defp plain_format_deps([], _, acc), do: acc

  defp plain_format_deps([{dep, deps} | tail], depth, acc) do
    dep_list = [
      "#{String.duplicate(" ", depth)}#{dep}" |
      plain_format_deps(deps, depth + @plain_indent, [])
    ]
    plain_format_deps(tail, depth, dep_list ++ acc)
  end

  defp plain_format_deps([dep | tail], depth, acc) do
    plain_format_deps(tail, depth, ["#{String.duplicate(" ", depth)}#{dep}" | acc])
  end

  defp dot_format_deps([], _, acc), do: acc

  defp dot_format_deps([{dep, deps} | tail], from, acc) do
    dep_list = [
      dot_line(dep, from) |
      dot_format_deps(deps, dep, [])
    ]
    dot_format_deps(tail, nil, dep_list ++ acc)
  end

  defp dot_format_deps([dep | tail], from, acc) do
    dot_format_deps(tail, from, [dot_line(dep, from) | acc])
  end

  defp dot_line(dep, nil), do: ~s(  "#{dep}")
  defp dot_line(dep, from), do: ~s(  "#{from}" -> "#{dep}")
end

