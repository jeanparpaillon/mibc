defmodule Mix.Tasks.Compile.Mib do
  use Mix.Task.Compiler
  require Logger
  import Mix.Compilers.Erlang

  @recursive true
  @manifest ".compile.mib"

  @moduledoc """
  Compiles SNMP MIBs.

  When this task runs, it will first check the modification times of
  all files to be compiled and if they haven't been
  changed since the last compilation, it will not compile
  them. If any of them have changed, it compiles
  everything.

  For this reason, the task touches your `:compile_path`
  directory and sets the modification time to the current
  time and date at the end of each compilation. You can
  force compilation regardless of modification times by passing
  the `--force` option.

  ## Command line options

    * `--force` - forces compilation regardless of modification times

  ## Configuration

    * `:mib_include_path` - directory for adding include files.
      Defaults to `"include"`.

    * `:mib_options` - compilation options that apply to Erlang's
      compiler. Defaults to `[:debug_info]`.

      For a complete list of options,
      see [`:snmpc.compile/2`](http://www.erlang.org/doc/man/snmpc.html#compile-2).
  """

  @doc """
  Runs this task.
  """
  @spec run(OptionParser.argv()) :: :ok | :noop
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])
    project = Mix.Project.config()
    manifest = Path.join(Mix.Project.manifest_path(), @manifest)

    mib_src = "mibs"
    mib_dest = Path.join([Mix.Project.app_path(project), "priv", "mibs"])
    mib_hrl_dest = Path.join([File.cwd!(), project[:erlc_include_path]])

    mib_includes =
      Keyword.get(project, :mib_include_path, []) ++ ['#{mib_dest}' | project[:erlc_paths]]

    compile(manifest, [{mib_src, mib_dest}], :mib, :bin, opts, fn
      input, output ->
        outdir = Path.dirname(output)
        if not File.exists?(outdir), do: :ok = File.mkdir_p!(outdir)
        if not File.exists?(mib_hrl_dest), do: :ok = File.mkdir_p!(mib_hrl_dest)

        Logger.info("[MIB] Compile MIB: #{input}")

        {:ok, _} =
          :snmpc.compile(to_erl_file(input), [
            {:outdir, '#{outdir}'},
            {:i, mib_includes},
            {:group_check, false},
            :no_defs
          ])

        File.mkdir_p!(Path.join([Mix.Project.app_path(project), "priv", "mibs"]))

        :ok =
          File.cp!(
            input,
            Path.join([Mix.Project.app_path(project), "priv", "mibs", Path.basename(input)])
          )

        mib_name = Path.basename(input, ".mib")
        Logger.info("[MIB] Create MIB header: #{mib_name}")

        File.cd!(mib_dest, fn ->
          :ok = :snmpc.mib_to_hrl('#{mib_name}')

          hdr_name = "#{mib_name}.hrl"
          from = "./#{hdr_name}"
          to = Path.join([mib_hrl_dest, hdr_name])

          File.mkdir_p!(Path.join([Mix.Project.app_path(project), "include"]))
          :ok = File.cp!(from, Path.join([Mix.Project.app_path(project), "include", hdr_name]))

          Logger.info("Move #{from} to #{to}")
          :ok = File.rename(from, to)
        end)

        {:ok, nil, []}
    end)
  end

  @doc """
  Returns Erlang manifests.
  """
  def manifests, do: [manifest()]
  defp manifest, do: Path.join(Mix.Project.manifest_path(), @manifest)

  @doc """
  Cleans up compilation artifacts.
  """
  def clean do
    Mix.Compilers.Erlang.clean(manifest())
  end
end
