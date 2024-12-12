defmodule DaedalWeb.DaedalBeaconComponents do
  use DaedalWeb, :live_component

  attr :field, Phoenix.HTML.FormField

  def search_input(assigns) do
    ~H"""
    <input type="text" placeholder="Search Deployments" phx-debounce="150" id={@field.id} name={@field.name} value={@field.value} />
    """
  end

  attr :field, Phoenix.HTML.FormField

  def sort_checkbox(assigns) do
    ~H"""
    <input
      type="checkbox"
      phx-debounce="150"
      checked={@field.value == "desc"}
      value={if @field.value == "asc", do: "desc", else: "asc"}
      id={@field.id}
      name={@field.name}
      value={@field.value}
    />
    """
  end

  attr :deployment, DaedalBeacon.Deployment, required: true

  def deployment_minimal(assigns) do
    ~H"""
    <div class="relative flex flex-col my-2 bg-white shadow-sm border border-slate-300 rounded-lg w-min" id={@deployment.node}>
      <.link patch={~p"/beacon/deployments/#{encode_uri_safe(@deployment.node)}"}>
        <div class="p-4">
          <h5 class="mb-2 text-slate-800 text-l font-semibold">
            {@deployment.node}
          </h5>
          <p class="text-slate-600 leading-normal font-light">
            {@deployment.name} ({@deployment.version})
          </p>
        </div>
      </.link>
    </div>
    """
  end

  attr :deployment, DaedalBeacon.Deployment, required: true

  def deployment_full(assigns) do
    ~H"""
    <section>
      <h1>{@deployment.name} ({@deployment.version})</h1>
      <p>Node: {@deployment.node}</p>
      <.metadata metadata={@deployment.metadata} />
      <.neighbors neighbors={@deployment.neighbors} />
      <.system_info system_info={@deployment.system_info} />
      <p>Tasks: <pre>{inspect(@deployment.daedal_remote_tasks, pretty: true, limit: :infinity, width: 0)}</pre></p>
      <.applications applications={@deployment.applications} />
    </section>
    """
  end

  attr :metadata, :list, required: true

  def metadata(assigns) do
    case assigns[:metadata] do
      [] ->
        ~H"""
        """

      _ ->
        ~H"""
        <section>
          <h2>Metadata</h2>
          <dl>
            <%= for {key, value} <- @metadata do %>
              <dt>{key}</dt>
              <dd>{inspect(value)}</dd>
            <% end %>
          </dl>
        </section>
        """
    end
  end

  attr :neighbors, :list, required: true

  def neighbors(assigns) do
    ~H"""
    <section>
      <h2>Neighbors</h2>
      <ul>
        <%= for {type, nodes} when nodes != [] <- @neighbors do %>
          <li id={type}>
            <strong>{type}:</strong>
            <ul>
              <%= for node <- nodes do %>
                <li id={"#{type}-#{node}"}>
                  <.link patch={~p"/beacon/deployments/#{encode_uri_safe(node)}"}>
                    - {node}
                  </.link>
                </li>
              <% end %>
            </ul>
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  attr :system_info, DaedalBeacon.Deployment.SystemInfo, required: true

  def system_info(assigns) do
    ~H"""
    <article>
      <h2>System Info</h2>
      <.os_info os_info={@system_info.os_info} />
      <.cpu_info cpu_info={@system_info.cpu_info} />
      <.version_info version_info={@system_info.version_info} />
    </article>
    """
  end

  attr :os_info, DaedalBeacon.Deployment.OSInfo, required: true

  def os_info(assigns) do
    ~H"""
    <section>
      <h3>OS Info</h3>
      <p>Architecture: {@os_info.system_architecture}</p>
      <p>Wordsize: {@os_info.wordsize}</p>
      <p>Threads: {@os_info.threads}</p>
      <p>Kernel Poll: {@os_info.kernel_poll}</p>
      <p>Time Warp Mode: {@os_info.time_warp_mode}</p>
    </section>
    """
  end

  attr :cpu_info, DaedalBeacon.Deployment.CPUInfo, required: true

  def cpu_info(assigns) do
    ~H"""
    <section>
      <h3>CPU Info</h3>
      <p>Topology: <pre><%= inspect(@cpu_info.cpu_topology, pretty: true, limit: :infinity) %></pre></p>
      <p>SMP Support: {@cpu_info.smp_support}</p>
      <p>Dirty CPU Schedulers: {@cpu_info.dirty_cpu_schedulers}</p>
      <p>Dirty IO Schedulers: {@cpu_info.dirty_io_schedulers}</p>
      <p>Emulator Flavor: {@cpu_info.emu_flavor}</p>
    </section>
    """
  end

  attr :version_info, DaedalBeacon.Deployment.VersionInfo, required: true

  def version_info(assigns) do
    ~H"""
    <section>
      <h3>Version Info</h3>
      <p>OTP Release: {@version_info.otp_release}</p>
      <p>ERTS Version: {@version_info.erts_version}</p>
      <p>Emulator Type: {@version_info.emu_type}</p>
    </section>
    """
  end

  attr :applications, :list, required: true

  def applications(assigns) do
    ~H"""
    <article>
      <h2>Applications</h2>
      <%= for {_name, application} <- @applications do %>
        <.application application={application} />
      <% end %>
    </article>
    """
  end

  attr :application, DaedalBeacon.Deployment.Applications, required: true

  def application(assigns) do
    ~H"""
    <section id={@application.name}>
      <h3><strong>{@application.name} ({@application.version})</strong></h3>
      <p>{@application.description}</p>
      <pre>{inspect(@application.spec, pretty: true, limit: :infinity, width: 0)}</pre>
    </section>
    """
  end

  defp encode_uri_safe(value) when is_atom(value), do: URI.encode(Atom.to_string(value))
  defp encode_uri_safe(value) when is_binary(value), do: URI.encode(value)
end
