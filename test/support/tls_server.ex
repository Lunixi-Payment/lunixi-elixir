defmodule Lunixi.TestTLS do
  @moduledoc false
  def start(handler) do
    directory = Path.join(System.tmp_dir!(), "lunixi-tls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    key = Path.join(directory, "key.pem")
    cert = Path.join(directory, "cert.pem")

    ca_key = Path.join(directory, "ca.key")
    ca_cert = Path.join(directory, "ca.pem")
    csr = Path.join(directory, "server.csr")
    extensions = Path.join(directory, "extensions.cnf")

    File.write!(
      extensions,
      "subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n"
    )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          ca_key,
          "-out",
          ca_cert,
          "-days",
          "1",
          "-subj",
          "/CN=Lunixi Synthetic Test CA",
          "-addext",
          "basicConstraints=critical,CA:TRUE"
        ],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-new",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          key,
          "-out",
          csr,
          "-subj",
          "/CN=localhost"
        ],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "x509",
          "-req",
          "-in",
          csr,
          "-CA",
          ca_cert,
          "-CAkey",
          ca_key,
          "-CAcreateserial",
          "-out",
          cert,
          "-days",
          "1",
          "-extfile",
          extensions
        ],
        stderr_to_stdout: true
      )

    [{:Certificate, der, _}] = :public_key.pem_decode(File.read!(ca_cert))

    parent = self()

    pid =
      spawn(fn ->
        {:ok, listener} =
          :ssl.listen(0, [
            :binary,
            active: false,
            reuseaddr: true,
            certfile: String.to_charlist(cert),
            keyfile: String.to_charlist(key)
          ])

        {:ok, {_, port}} = :ssl.sockname(listener)
        send(parent, {:tls_ready, self(), port})
        accept(listener, handler)
      end)

    receive do
      {:tls_ready, ^pid, port} ->
        ExUnit.Callbacks.on_exit(fn ->
          Process.exit(pid, :kill)
          File.rm_rf!(directory)
        end)

        %{pid: pid, url: "https://localhost:#{port}", certificate: der}
    after
      5_000 -> raise "TLS test server did not start"
    end
  end

  def config(server, options \\ []) do
    fixture =
      Jason.decode!(File.read!(Path.expand("../fixtures/canonical-vectors.json", __DIR__)))

    struct!(
      Lunixi.Config,
      [
        base_url: server.url,
        key_id: "mk_test_fixture",
        private_key: fixture["privateSeed"],
        additional_ca_certificates: [server.certificate]
      ] ++ options
    )
  end

  defp accept(listener, handler) do
    case :ssl.transport_accept(listener) do
      {:ok, socket} ->
        child =
          spawn_link(fn ->
            receive do
              {:socket, socket} -> serve(socket, handler)
            end
          end)

        :ok = :ssl.controlling_process(socket, child)
        send(child, {:socket, socket})
        accept(listener, handler)

      _ ->
        :ok
    end
  end

  defp serve(socket, handler) do
    with {:ok, socket} <- :ssl.handshake(socket, 5_000),
         {:ok, request} <- read_request(socket, "") do
      reply = handler.(request)

      {status, body, extra} =
        case reply do
          {status, body} -> {status, body, []}
          full -> full
        end

      headers =
        [
          {"content-type", "application/json"},
          {"content-length", byte_size(body)},
          {"connection", "close"}
        ] ++ extra

      response = [
        "HTTP/1.1 #{status} Response\r\n",
        Enum.map(headers, fn {key, value} -> "#{key}: #{value}\r\n" end),
        "\r\n",
        body
      ]

      :ssl.send(socket, response)
      :ssl.close(socket)
    end
  end

  defp read_request(socket, raw) do
    case :binary.match(raw, "\r\n\r\n") do
      {index, 4} ->
        <<head::binary-size(^index), _::binary-size(4), body::binary>> = raw
        [first | lines] = String.split(head, "\r\n")
        [method, path, _] = String.split(first, " ")

        headers =
          Map.new(lines, fn line ->
            [k, v] = String.split(line, ":", parts: 2)
            {String.downcase(k), String.trim(v)}
          end)

        length = String.to_integer(Map.get(headers, "content-length", "0"))

        case read_body(socket, body, length) do
          {:ok, body} -> {:ok, %{method: method, path: path, headers: headers, body: body}}
          error -> error
        end

      :nomatch ->
        case :ssl.recv(socket, 0, 5_000) do
          {:ok, chunk} -> read_request(socket, raw <> chunk)
          error -> error
        end
    end
  end

  defp read_body(_, body, length) when byte_size(body) >= length, do: {:ok, body}

  defp read_body(socket, body, length) do
    case :ssl.recv(socket, 0, 5_000) do
      {:ok, chunk} -> read_body(socket, body <> chunk, length)
      error -> error
    end
  end
end
