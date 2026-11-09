defmodule Gallformers.Credo.Checks.Architecture.SingleEntryPoint do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [capabilities: []],
    explanations: [
      check: """
      A shared capability (a name search, the review's decisions, taxon
      creation) is reached through one named module only (matter c800).

      A second caller usually means a second copy of the mechanic: its own
      search, its own result wording, its own decide path. Call the owner
      instead, or extend it.

      Each capability in `.credo.exs` names its functions, its scope (a path
      prefix), its owners, and the `pending` callers that predate the check,
      each with the matter that moves it. A pending caller that no longer
      makes the call is reported too, so the list only shrinks.
      """,
      params: [
        capabilities: """
        A list of `%{name:, calls:, scope:, owners:, pending:}`. `calls` is a
        list of `{Module, [function]}` or `{:accessor, [function]}`, the
        accessor being a local function returning a module, as in
        `wcvp_lookup().search(q)`. `pending` is a list of `{Module, matter}`.
        """
      ]
    ]

  alias Credo.IssueMeta

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    {calls, modules} = scan(Credo.SourceFile.ast(source_file))

    for cap <- Params.get(params, :capabilities, __MODULE__),
        String.starts_with?(source_file.filename, cap.scope),
        issue <- uninvited(cap, calls, issue_meta) ++ stale(cap, calls, modules, issue_meta),
        do: issue
  end

  # Calls to the capability from a module that is neither an owner nor pending.
  defp uninvited(cap, calls, issue_meta) do
    allowed = cap.owners ++ Enum.map(cap.pending, &elem(&1, 0))

    for {caller, target, fun, line} <- calls,
        calls?(cap, target, fun),
        caller not in allowed do
      format_issue(issue_meta,
        message:
          "#{inspect(caller)} calls #{name(target, fun)} (#{cap.name}). " <>
            "Go through #{Enum.map_join(cap.owners, " or ", &inspect/1)} instead.",
        trigger: to_string(fun),
        line_no: line
      )
    end
  end

  # Pending callers defined in this file that no longer make the call.
  defp stale(cap, calls, modules, issue_meta) do
    for {module, matter} <- cap.pending,
        line = modules[module],
        line != nil,
        not Enum.any?(calls, fn {c, t, f, _} -> c == module and calls?(cap, t, f) end) do
      format_issue(issue_meta,
        message:
          "#{inspect(module)} no longer calls #{cap.name}: remove it from the capability's " <>
            "pending list in .credo.exs (matter #{matter}).",
        trigger: inspect(module),
        line_no: line
      )
    end
  end

  defp calls?(cap, target, fun),
    do: Enum.any?(cap.calls, fn {t, funs} -> target(t) == target and fun in funs end)

  defp target(module_or_accessor) do
    if module?(module_or_accessor), do: module_or_accessor, else: {:accessor, module_or_accessor}
  end

  defp module?(atom), do: String.starts_with?(Atom.to_string(atom), "Elixir.")

  defp name({:accessor, accessor}, fun), do: "#{accessor}().#{fun}"
  defp name(module, fun), do: "#{inspect(module)}.#{fun}"

  # The remote calls in a file, each as `{caller module, target, function,
  # line}`, and the modules it defines with their lines. Aliases are
  # followed, including multi-aliases and `as:`.
  defp scan(ast) do
    state = %{stack: [], calls: [], modules: %{}}
    {_ast, state} = Macro.traverse(ast, state, &pre/2, &post/2)
    {state.calls, state.modules}
  end

  defp pre({:defmodule, meta, [{:__aliases__, _, parts} | _]} = ast, state) do
    parent = List.first(state.stack)
    module = Module.concat(if(parent, do: [parent.module | parts], else: parts))
    aliases = if parent, do: parent.aliases, else: %{}
    frame = %{module: module, aliases: aliases}

    {ast,
     %{state | stack: [frame | state.stack], modules: Map.put(state.modules, module, meta[:line])}}
  end

  defp pre({:alias, _, [{:__aliases__, _, parts}]} = ast, state),
    do: {ast, add_alias(state, List.last(parts), parts)}

  defp pre({:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as]}]]} = ast, state),
    do: {ast, add_alias(state, as, parts)}

  defp pre({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = ast, state) do
    state =
      for {:__aliases__, _, parts} <- children,
          reduce: state,
          do: (acc -> add_alias(acc, List.last(parts), base ++ parts))

    {ast, state}
  end

  defp pre({{:., _, [{:__aliases__, _, parts}, fun]}, meta, _args} = ast, state)
       when is_atom(fun),
       do: {ast, add_call(state, expand(state, parts), fun, meta)}

  defp pre({{:., _, [{accessor, _, args}, fun]}, meta, _args} = ast, state)
       when is_atom(accessor) and is_list(args) and is_atom(fun),
       do: {ast, add_call(state, {:accessor, accessor}, fun, meta)}

  defp pre(ast, state), do: {ast, state}

  defp post({:defmodule, _, _} = ast, %{stack: [_ | rest]} = state),
    do: {ast, %{state | stack: rest}}

  defp post(ast, state), do: {ast, state}

  defp add_alias(%{stack: [frame | rest]} = state, name, parts) when is_atom(name) do
    case expand(state, parts) do
      nil ->
        state

      module ->
        %{state | stack: [%{frame | aliases: Map.put(frame.aliases, name, module)} | rest]}
    end
  end

  defp add_alias(state, _name, _parts), do: state

  defp add_call(%{stack: [frame | _]} = state, target, fun, meta) when target != nil,
    do: %{state | calls: [{frame.module, target, fun, meta[:line]} | state.calls]}

  defp add_call(state, _target, _fun, _meta), do: state

  # A module name with its first part resolved through the aliases in
  # scope; nil for names built from `__MODULE__` and the like.
  defp expand(%{stack: stack}, [first | rest] = parts) when is_atom(first) do
    aliases = if stack == [], do: %{}, else: hd(stack).aliases

    case aliases do
      %{^first => module} -> Module.concat([module | rest])
      _ -> Module.concat(parts)
    end
  end

  defp expand(_state, _parts), do: nil
end
