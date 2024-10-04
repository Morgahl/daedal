defmodule Daedal.Beacon.Deployment do
  @moduledoc """
   `Daedal.Beacon.Deployment` is a struct that represents a deployment in the Beacon server. This is
   used to keep track of the deployments that have registered with the Beacon server.
  """

  defmodule Applications do
    defstruct [
      :name,
      :description,
      :version,
      :spec
    ]

    @type t :: %{
            name: atom(),
            description: String.t(),
            version: String.t(),
            spec: Keyword.t()
          }

    @spec new() :: [t()]
    def new do
      for {app, description, version} <- :application.which_applications() do
        spec = Application.spec(app)

        {app,
         %__MODULE__{
           name: app,
           description: List.to_string(description),
           version: List.to_string(version),
           spec: Keyword.drop(spec, [:description, :vsn])
         }}
      end
    end
  end

  defmodule CPUInfo do
    defstruct [
      :cpu_topology,
      :smp_support,
      :dirty_cpu_schedulers,
      :dirty_io_schedulers,
      :emu_flavor
    ]

    @type t :: %__MODULE__{
            cpu_topology: list(),
            smp_support: boolean(),
            dirty_cpu_schedulers: integer(),
            dirty_io_schedulers: integer(),
            emu_flavor: atom()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        cpu_topology: :erlang.system_info(:cpu_topology),
        smp_support: :erlang.system_info(:smp_support),
        dirty_cpu_schedulers: :erlang.system_info(:dirty_cpu_schedulers),
        dirty_io_schedulers: :erlang.system_info(:dirty_io_schedulers),
        emu_flavor: :erlang.system_info(:emu_flavor)
      }
    end
  end

  defmodule OSInfo do
    defstruct [
      :time_warp_mode,
      :kernel_poll,
      :threads,
      :system_architecture,
      :wordsize
    ]

    @type t :: %__MODULE__{
            time_warp_mode: atom(),
            kernel_poll: boolean(),
            threads: boolean(),
            system_architecture: String.t(),
            wordsize: 4 | 8
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        time_warp_mode: :erlang.system_info(:time_warp_mode),
        kernel_poll: :erlang.system_info(:kernel_poll),
        threads: :erlang.system_info(:threads),
        system_architecture: List.to_string(:erlang.system_info(:system_architecture)),
        wordsize: :erlang.system_info(:wordsize)
      }
    end
  end

  defmodule VersionInfo do
    defstruct [
      :otp_release,
      :erts_version,
      :emu_type
    ]

    @type t :: %__MODULE__{
            otp_release: String.t(),
            erts_version: String.t(),
            emu_type: atom()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        otp_release: List.to_string(:erlang.system_info(:otp_release)),
        erts_version: List.to_string(:erlang.system_info(:version)),
        emu_type: :erlang.system_info(:emu_type)
      }
    end
  end

  defmodule SystemInfo do
    defstruct [
      :os_info,
      :cpu_info,
      :version_info
    ]

    @type t :: %__MODULE__{
            os_info: OSInfo.t(),
            cpu_info: CPUInfo.t(),
            version_info: VersionInfo.t()
          }

    @spec new() :: t()
    def new do
      %__MODULE__{
        os_info: OSInfo.new(),
        cpu_info: CPUInfo.new(),
        version_info: VersionInfo.new()
      }
    end
  end

  defstruct [
    :node,
    :name,
    :version,
    :applications,
    :system_info,
    :metadata
  ]

  @type t :: %__MODULE__{
          node: atom(),
          name: atom(),
          version: any(),
          applications: [Applications.t()],
          system_info: SystemInfo.t(),
          metadata: Keyword.t()
        }

  @spec new() :: t()
  @spec new(Keyword.t()) :: t()
  def new(metadata \\ []) do
    app = get_application()

    version =
      case get_application_key(app, :vsn) do
        version when is_list(version) -> List.to_string(version)
        version -> version
      end

    %__MODULE__{
      node: Node.self(),
      name: app,
      version: version,
      applications: Applications.new(),
      system_info: SystemInfo.new(),
      metadata: metadata
    }
  end

  defp get_application() do
    case :application.get_application() do
      {:ok, app} -> app
      :undefined -> :undefined
    end
  end

  defp get_application_key(:undefined, _), do: :undefined

  defp get_application_key(app, key) do
    case :application.get_key(app, key) do
      {:ok, value} -> value
      :undefined -> :undefined
    end
  end
end
